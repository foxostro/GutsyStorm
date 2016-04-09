//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSActiveRegion.h"
#import "GSFrustum.h"
#import "GSVoxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"
#import "GSGridItem.h"
#import "GSGridVAO.h"
#import "GSChunkVAO.h"

#define LOG_PERF 0
#import "Stopwatch.h"


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    vector_float3 _activeRegionExtent;

    /* List of GSChunkVAO which are within the camera frustum. */
    NSArray<GSChunkVAO *> *_vaosInCameraFrustum;
    NSLock *_lockVAOsInCameraFrustum;

    /* Used to generate and retrieve Vertex Array Objects. */
    GSGridVAO *_gridVAO;

    /* Dispatch queue for processing updates to _vaosInCameraFrustum. */
    dispatch_queue_t _updateQueue;
    dispatch_semaphore_t _semaQueueDepth;

    /* Flag indicates that the queue should shutdown. */
    BOOL _shouldShutdown;
}

- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                             camera:(nonnull GSCamera *)camera
                                            vaoGrid:(nonnull GSGridVAO *)gridVAO
{
    self = [super init];
    if (self) {
        assert(camera);
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _vaosInCameraFrustum = nil;
        _lockVAOsInCameraFrustum = [NSLock new];
        _gridVAO = gridVAO;
        _updateQueue = dispatch_queue_create("GSActiveRegion._updateQueue", DISPATCH_QUEUE_SERIAL);
        _semaQueueDepth = dispatch_semaphore_create(2);
        _shouldShutdown = NO;

        [self notifyOfChangeInActiveRegionVAOs];
    }
    
    return self;
}

- (void)draw
{
#if LOG_PERF
    uint64_t startAbs = stopwatchStart();
#endif

    NSArray<GSChunkVAO *> *vaos;

    if (!_shouldShutdown) {

        [_lockVAOsInCameraFrustum lock];
        vaos = _vaosInCameraFrustum;
        [_lockVAOsInCameraFrustum unlock];

        for(GSChunkVAO *vao in vaos)
        {
            [vao draw];
        }
    }

#if LOG_PERF
    uint64_t elapsedNs = stopwatchEnd(startAbs);
    float elapsedMs = (float)elapsedNs / (float)NSEC_PER_MSEC;
    NSLog(@"draw: %.3f ms (count=%lu)", elapsedMs, vaos.count);
#endif
}

- (void)updateVAOsInCameraFrustum
{
#if LOG_PERF
    uint64_t startAbs = stopwatchStart();
#endif

    BOOL didSkipSomeCreationTasks = NO;
    NSMutableArray<GSChunkVAO *> *vaosInCameraFrustum = [NSMutableArray<GSChunkVAO *> new];
    NSArray<GSBoxedVector *> *points = [self pointsInCameraFrustum];
    
    NSUInteger vaoGenLimit = 2;
    NSUInteger vaoGenCount = 0;
    
    for(GSBoxedVector *boxedPosition in points)
    {
        if (_shouldShutdown) {
            return;
        } else {
            BOOL createIfMissing = vaoGenCount < vaoGenLimit;
            BOOL vaoGenDidHappen = NO;
            GSChunkVAO *vao = nil;
            [_gridVAO objectAtPoint:[boxedPosition vectorValue]
                            blocking:YES
                              object:&vao
                     createIfMissing:createIfMissing
                       didCreateItem:&vaoGenDidHappen];

            if (vao) {
                vaoGenCount += vaoGenDidHappen ? 1 : 0;
                [vaosInCameraFrustum addObject:vao];
            } else {
                didSkipSomeCreationTasks = !createIfMissing;
            }
        }
    }

    /* Publish the list of chunk VAOs which are in the camera frustum.
     * This is consumed on the rendering thread by -draw.
     */
    [_lockVAOsInCameraFrustum lock];
    _vaosInCameraFrustum = vaosInCameraFrustum;
    [_lockVAOsInCameraFrustum unlock];

    if (didSkipSomeCreationTasks) {
        [self notifyOfChangeInActiveRegionVAOs]; // Remember to pick up where we left off later.
    }

#if LOG_PERF
    uint64_t elapsedNs = stopwatchEnd(startAbs);
    float elapsedMs = (float)elapsedNs / (float)NSEC_PER_MSEC;
    NSLog(@"updateVAOsInCameraFrustum: %.3f ms (count=%lu)", elapsedMs, vaosInCameraFrustum.count);
#endif
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        [self notifyOfChangeInActiveRegionVAOs];
    }
}

- (nonnull NSArray<GSBoxedVector *> *)pointsInCameraFrustum
{
    NSMutableArray<GSBoxedVector *> *points = [NSMutableArray<GSBoxedVector *> new];

    GSFrustum *frustum = _camera.frustum;
    const vector_float3 center = _camera.cameraEye;
    const long activeRegionExtentX = _activeRegionExtent.x/CHUNK_SIZE_X;
    const long activeRegionExtentZ = _activeRegionExtent.z/CHUNK_SIZE_Z;
    const long activeRegionSizeY = _activeRegionExtent.y/CHUNK_SIZE_Y;
    
    vector_long3 p, minP, maxP;
    
    minP = GSMakeIntegerVector3(-activeRegionExtentX, 0, -activeRegionExtentZ);
    maxP = GSMakeIntegerVector3(activeRegionExtentX, activeRegionSizeY, activeRegionExtentZ);
    
    FOR_BOX(p, minP, maxP)
    {
        assert((p.x+activeRegionExtentX) >= 0);
        assert(p.x < activeRegionExtentX);
        assert((p.z+activeRegionExtentZ) >= 0);
        assert(p.z < activeRegionExtentZ);
        assert(p.y >= 0);
        assert(p.y < activeRegionSizeY);
        
        vector_float3 p1 = (vector_float3){center.x + p.x*CHUNK_SIZE_X, p.y*CHUNK_SIZE_Y, center.z + p.z*CHUNK_SIZE_Z};
        
        vector_float3 centerP = (vector_float3){floorf(p1.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                                                floorf(p1.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                                                floorf(p1.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2};
        
        vector_float3 corners[8];
        
        corners[0] = GSMinCornerForChunkAtPoint(centerP);
        corners[1] = corners[0] + (vector_float3){CHUNK_SIZE_X, 0,            0};
        corners[2] = corners[0] + (vector_float3){CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z};
        corners[3] = corners[0] + (vector_float3){0,            0,            CHUNK_SIZE_Z};
        corners[4] = corners[0] + (vector_float3){0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z};
        corners[5] = corners[0] + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};
        corners[6] = corners[0] + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y, 0};
        corners[7] = corners[0] + (vector_float3){0,            CHUNK_SIZE_Y, 0};

        if(GSFrustumOutside != [frustum boxInFrustumWithBoxVertices:corners]) {
            [points addObject:[GSBoxedVector boxedVectorWithVector:centerP]];
        }
    }
    
    [points sortUsingComparator:^NSComparisonResult(GSBoxedVector *p1, GSBoxedVector *p2) {
        float d1 = vector_distance([p1 vectorValue], center);
        float d2 = vector_distance([p2 vectorValue], center);
        
        if (d1 > d2) {
            return NSOrderedDescending;
        } else if (d1 > d2) {
            return NSOrderedAscending;
        } else {
            return NSOrderedSame;
        }
    }];
    
    return points;
}

- (void)notifyOfChangeInActiveRegionVAOs
{
    if(0 == dispatch_semaphore_wait(_semaQueueDepth, DISPATCH_TIME_NOW)) {
        dispatch_async(_updateQueue, ^{
            if (!_shouldShutdown) {
                [self updateVAOsInCameraFrustum];
            }
            dispatch_semaphore_signal(_semaQueueDepth);
        });
    }
}

- (void)shutdown
{
    _shouldShutdown = YES;

    dispatch_barrier_sync(_updateQueue, ^{
        [_lockVAOsInCameraFrustum lock];
        _vaosInCameraFrustum = nil;
        [_lockVAOsInCameraFrustum unlock];
    });
}

@end
