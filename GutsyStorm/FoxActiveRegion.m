//
//  FoxActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxActiveRegion.h"
#import "FoxFrustum.h"
#import "GSVoxel.h"
#import "FoxBoxedVector.h"
#import "GSCamera.h"
#import "GSGridItem.h"
#import "GSGridVBOs.h"
#import "FoxChunkVBOs.h"

#define LOG_PERF 0

#if LOG_PERF
#import <mach/mach.h>
#import <mach/mach_time.h>

static inline uint64_t stopwatchStart()
{
    return mach_absolute_time();
}

static inline uint64_t stopwatchEnd(uint64_t startAbs)
{
    static mach_timebase_info_data_t sTimebaseInfo;
    static dispatch_once_t onceToken;
    
    uint64_t endAbs = mach_absolute_time();
    uint64_t elapsedAbs = endAbs - startAbs;
    
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&(sTimebaseInfo));
    });
    assert(sTimebaseInfo.denom != 0);
    uint64_t elapsedNs = elapsedAbs * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return elapsedNs;
}
#endif


@implementation FoxActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    vector_float3 _activeRegionExtent;

    /* List of FoxChunkVBOs which are within the camera frustum. */
    NSArray<FoxChunkVBOs *> *_vbosInCameraFrustum;
    NSLock *_lockVbosInCameraFrustum;

    /* Used to generate and retrieve VBOs. */
    GSGridVBOs *_gridVBOs;

    /* Dispatch queue for processing updates to _vbosInCameraFrustum. */
    dispatch_queue_t _updateQueue;
    dispatch_semaphore_t _semaQueueDepth;

    /* Flag indicates that the queue should shutdown. */
    BOOL _shouldShutdown;
}

- (instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                    camera:(GSCamera *)camera
                                   vboGrid:(GSGridVBOs *)gridVBOs
{
    self = [super init];
    if (self) {
        assert(camera);
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _vbosInCameraFrustum = nil;
        _lockVbosInCameraFrustum = [NSLock new];
        _gridVBOs = gridVBOs;
        _updateQueue = dispatch_queue_create("FoxActiveRegion._updateQueue", DISPATCH_QUEUE_SERIAL);
        _semaQueueDepth = dispatch_semaphore_create(2);
        _shouldShutdown = NO;

        [self notifyOfChangeInActiveRegionVBOs];
    }
    
    return self;
}

- (void)draw
{
#if LOG_PERF
    uint64_t startAbs = stopwatchStart();
#endif

    NSArray<FoxChunkVBOs *> *vbos;

    if (!_shouldShutdown) {

        [_lockVbosInCameraFrustum lock];
        vbos = _vbosInCameraFrustum;
        [_lockVbosInCameraFrustum unlock];

        for(FoxChunkVBOs *vbo in vbos)
        {
            [vbo draw];
        }
    }

#if LOG_PERF
    uint64_t elapsedNs = stopwatchEnd(startAbs);
    float elapsedMs = (float)elapsedNs / (float)NSEC_PER_MSEC;
    NSLog(@"draw: %.3f ms (count=%lu)", elapsedMs, vbos.count);
#endif
}

- (void)updateVBOsInCameraFrustum
{
#if LOG_PERF
    uint64_t startAbs = stopwatchStart();
#endif
    
    BOOL didSkipSomeCreationTasks = NO;
    NSMutableArray<FoxChunkVBOs *> *vbosInCameraFrustum = [NSMutableArray<FoxChunkVBOs *> new];
    NSArray<FoxBoxedVector *> *points = [self pointsInCameraFrustum];
    
    NSUInteger vboGenLimit = 2;
    NSUInteger vboGenCount = 0;
    
    for(FoxBoxedVector *boxedPosition in points)
    {
        if (_shouldShutdown) {
            return;
        } else {
            BOOL createIfMissing = vboGenCount < vboGenLimit;
            BOOL vboGenDidHappen = NO;
            FoxChunkVBOs *vbo = nil;
            [_gridVBOs objectAtPoint:[boxedPosition vectorValue]
                            blocking:YES
                              object:&vbo
                     createIfMissing:createIfMissing
                       didCreateItem:&vboGenDidHappen];

            if (vbo) {
                vboGenCount += vboGenDidHappen ? 1 : 0;
                [vbosInCameraFrustum addObject:vbo];
            }
            
            if (!createIfMissing) {
                didSkipSomeCreationTasks = YES;
            }
        }
    }

    /* Publish the list of chunk VBOs which are in the camera frustum.
     * This is consumed on the rendering thread by -draw.
     */
    [_lockVbosInCameraFrustum lock];
    _vbosInCameraFrustum = vbosInCameraFrustum;
    [_lockVbosInCameraFrustum unlock];
    
    if (didSkipSomeCreationTasks) {
        [self notifyOfChangeInActiveRegionVBOs]; // Remember to pick up where we left off later.
    }

#if LOG_PERF
    uint64_t elapsedNs = stopwatchEnd(startAbs);
    float elapsedMs = (float)elapsedNs / (float)NSEC_PER_MSEC;
    NSLog(@"updateVBOsInCameraFrustum: %.3f ms (count=%lu)", elapsedMs, vbosInCameraFrustum.count);
#endif
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        [self notifyOfChangeInActiveRegionVBOs];
    }
}

- (NSArray<FoxBoxedVector *> *)pointsInCameraFrustum
{
    NSMutableArray<FoxBoxedVector *> *points = [NSMutableArray<FoxBoxedVector *> new];

    FoxFrustum *frustum = _camera.frustum;
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

        if(FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:corners]) {
            [points addObject:[FoxBoxedVector boxedVectorWithVector:centerP]];
        }
    }
    
    [points sortUsingComparator:^NSComparisonResult(FoxBoxedVector *p1, FoxBoxedVector *p2) {
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

- (void)notifyOfChangeInActiveRegionVBOs
{
    if(0 == dispatch_semaphore_wait(_semaQueueDepth, DISPATCH_TIME_NOW)) {
        dispatch_async(_updateQueue, ^{
            if (!_shouldShutdown) {
                [self updateVBOsInCameraFrustum];
            }
            dispatch_semaphore_signal(_semaQueueDepth);
        });
    }
}

- (void)shutdown
{
    _shouldShutdown = YES;

    dispatch_barrier_sync(_updateQueue, ^{
        [_lockVbosInCameraFrustum lock];
        _vbosInCameraFrustum = nil;
        [_lockVbosInCameraFrustum unlock];
    });
}

@end
