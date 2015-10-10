//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSActiveRegion.h"
#import "GSFrustum.h"
#import "Voxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"
#import "GSGridItem.h"
#import "GSGridVBOs.h"
#import "GSChunkVBOs.h"

#define LOG_PERF 0

#if LOG_PERF
#import <mach/mach_time.h>
#endif


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    GLKVector3 _activeRegionExtent;

    /* List of GSChunkVBOs which are within the camera frustum. */
    NSArray *_vbosInCameraFrustum;
    NSLock *_lockVbosInCameraFrustum;

    /* Used to generate and retrieve VBOs. */
    GSGridVBOs *_gridVBOs;

    /* Dispatch queue for processing updates to _vbosInCameraFrustum. */
    dispatch_queue_t _updateQueue;
    dispatch_semaphore_t _semaQueueDepth;

    /* Flag indicates that the queue should shutdown. */
    BOOL _shouldShutdown;
}

- (instancetype)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
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
        _updateQueue = dispatch_queue_create("GSActiveRegion._updateQueue", DISPATCH_QUEUE_SERIAL);
        _semaQueueDepth = dispatch_semaphore_create(2);
        _shouldShutdown = NO;

        [self notifyOfChangeInActiveRegionVBOs];
    }
    
    return self;
}

- (void)draw
{
#if LOG_PERF
    uint64_t startAbs = mach_absolute_time();
#endif

    NSArray *vbos;

    if (!_shouldShutdown) {

        [_lockVbosInCameraFrustum lock];
        vbos = _vbosInCameraFrustum;
        [_lockVbosInCameraFrustum unlock];

        for(GSChunkVBOs *vbo in vbos)
        {
            [vbo draw];
        }
    }

#if LOG_PERF
    uint64_t endAbs = mach_absolute_time();
    uint64_t elapsedAbs = endAbs - startAbs;
    Nanoseconds elapsedNano = AbsoluteToNanoseconds( *(AbsoluteTime *) &elapsedAbs );
    uint64_t elapsedNs = *(uint64_t *)&elapsedNano;
    float elapsedMs = (float)elapsedNs / (float)NSEC_PER_MSEC;
    NSLog(@"draw: %.3f ms (count=%lu)", elapsedMs, vbos.count);
#endif
}

- (void)updateVBOsInCameraFrustum
{
#if LOG_PERF
    uint64_t startAbs = mach_absolute_time();
#endif
    
    BOOL didSkipSomeCreationTasks = NO;
    NSMutableArray *vbosInCameraFrustum = [[NSMutableArray alloc] init];
    NSArray *points = [self pointsInCameraFrustum];
    
    NSUInteger vboGenLimit = 2;
    NSUInteger vboGenCount = 0;
    
    for(GSBoxedVector *boxedPosition in points)
    {
        if (_shouldShutdown) {
            return;
        } else {
            BOOL createIfMissing = vboGenCount < vboGenLimit;
            BOOL vboGenDidHappen = NO;
            GSChunkVBOs *vbo = nil;
            [_gridVBOs objectAtPoint:[boxedPosition vectorValue]
                            blocking:NO
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
    uint64_t endAbs = mach_absolute_time();
    uint64_t elapsedAbs = endAbs - startAbs;
    Nanoseconds elapsedNano = AbsoluteToNanoseconds( *(AbsoluteTime *) &elapsedAbs );
    uint64_t elapsedNs = *(uint64_t *)&elapsedNano;
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

- (NSArray *)pointsInCameraFrustum
{
    NSMutableArray *points = [NSMutableArray new];

    GSFrustum *frustum = _camera.frustum;
    const GLKVector3 center = _camera.cameraEye;
    const ssize_t activeRegionExtentX = _activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = _activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = _activeRegionExtent.y/CHUNK_SIZE_Y;
    
    GSIntegerVector3 p, minP, maxP;
    
    minP = GSIntegerVector3_Make(-activeRegionExtentX, 0, -activeRegionExtentZ);
    maxP = GSIntegerVector3_Make(activeRegionExtentX, activeRegionSizeY, activeRegionExtentZ);
    
    FOR_BOX(p, minP, maxP)
    {
        assert((p.x+activeRegionExtentX) >= 0);
        assert(p.x < activeRegionExtentX);
        assert((p.z+activeRegionExtentZ) >= 0);
        assert(p.z < activeRegionExtentZ);
        assert(p.y >= 0);
        assert(p.y < activeRegionSizeY);
        
        GLKVector3 p1 = GLKVector3Make(center.x + p.x*CHUNK_SIZE_X, p.y*CHUNK_SIZE_Y, center.z + p.z*CHUNK_SIZE_Z);
        
        GLKVector3 centerP = GLKVector3Make(floorf(p1.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                                            floorf(p1.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                                            floorf(p1.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
        
        GLKVector3 corners[8];
        
        corners[0] = MinCornerForChunkAtPoint(centerP);
        corners[1] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GLKVector3Add(corners[0], GLKVector3Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GLKVector3Add(corners[0], GLKVector3Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GLKVector3Add(corners[0], GLKVector3Make(0,            CHUNK_SIZE_Y, 0));

        if(GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:corners]) {
            [points addObject:[GSBoxedVector boxedVectorWithVector:centerP]];
        }
    }
    
    [points sortUsingComparator:^NSComparisonResult(GSBoxedVector *p1, GSBoxedVector *p2) {
        float d1 = GLKVector3Distance([p1 vectorValue], center);
        float d2 = GLKVector3Distance([p2 vectorValue], center);
        
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
