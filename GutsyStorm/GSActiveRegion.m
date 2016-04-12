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


static const uint64_t GSChunkCreationBudget = 10 * NSEC_PER_MSEC; // chosen arbitrarily


static int chunkInFrustum(GSFrustum *frustum, vector_float3 p)
{
    vector_float3 corners[8];
    
    corners[0] = GSMinCornerForChunkAtPoint(p);
    corners[1] = corners[0] + (vector_float3){CHUNK_SIZE_X, 0,            0};
    corners[2] = corners[0] + (vector_float3){CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z};
    corners[3] = corners[0] + (vector_float3){0,            0,            CHUNK_SIZE_Z};
    corners[4] = corners[0] + (vector_float3){0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z};
    corners[5] = corners[0] + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};
    corners[6] = corners[0] + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y, 0};
    corners[7] = corners[0] + (vector_float3){0,            CHUNK_SIZE_Y, 0};
    
    return [frustum boxInFrustumWithBoxVertices:corners];
}


@interface GSActiveRegion ()

/* Flag indicates that the queue should shutdown. */
@property (atomic, readwrite) BOOL shouldShutdown;

@end


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    vector_float3 _activeRegionExtent;

    /* Used to generate and retrieve Vertex Array Objects. */
    GSGridVAO *_gridVAO;

    /* Dispatch Queue used for generating chunks asynchronously. */
    dispatch_queue_t _generationQueue;
    
    /* List of VAOs the display link thread will draw. */
    NSMutableSet<GSChunkVAO *> *_drawList;
    NSLock *_lockDrawList;
    
    /* The calculated set of chunk points in the camera frustum. */
    NSArray<GSBoxedVector *> *_cachedPointsInCameraFrustum;
    GSReaderWriterLock *_lockCachedPointsInCameraFrustum;
}

- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                             camera:(nonnull GSCamera *)camera
                                            vaoGrid:(nonnull GSGridVAO *)gridVAO
{
    NSParameterAssert(camera);
    NSParameterAssert(gridVAO);
    NSParameterAssert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
    NSParameterAssert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
    NSParameterAssert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

    if (self = [super init]) {
        _shouldShutdown = NO;
        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _gridVAO = gridVAO;
        _generationQueue = dispatch_queue_create("GSActiveRegion.generationQueue", DISPATCH_QUEUE_CONCURRENT);

        _drawList = [NSMutableSet new];
        _lockDrawList = [NSLock new];
        _lockDrawList.name = @"GSActiveRegion.lockDrawList";
        
        _cachedPointsInCameraFrustum = nil;
        _lockCachedPointsInCameraFrustum = [GSReaderWriterLock new];
        _lockCachedPointsInCameraFrustum.name = @"GSActiveRegion.lockCachedPointsInCameraFrustum";
    }
    
    return self;
}

- (void)_unlockedConstructDrawList
{
    BOOL anyChunksMissing = NO;
    
    [_lockCachedPointsInCameraFrustum lockForReading];
    NSObject<NSFastEnumeration> *points = [_cachedPointsInCameraFrustum copy];
    [_lockCachedPointsInCameraFrustum unlockForReading];
    
    for(GSBoxedVector *boxedPosition in points)
    {
        GSChunkVAO *vao = nil;
        
        [_gridVAO objectAtPoint:[boxedPosition vectorValue]
                       blocking:NO
                         object:&vao
                createIfMissing:NO];
        
        if (vao) {
            [_drawList addObject:vao];
        } else {
            anyChunksMissing = YES;
        }
    }
    
    if (anyChunksMissing) {
        [self needsChunkGeneration];
    }
}

- (void)draw
{
#if LOG_PERF
    uint64_t startAbs = stopwatchStart();
#endif

    if (self.shouldShutdown) {
        return;
    }

    [_lockDrawList lock];

    // First, remove any chunks from the list which are no longer in the camera frustum.
    {
        NSMutableArray *vaosToRemove = [[NSMutableArray alloc] initWithCapacity:_drawList.count];

        for(GSChunkVAO *vao in _drawList)
        {
            if(GSFrustumOutside == chunkInFrustum(_camera.frustum, vao.minP)) {
                [vaosToRemove addObject:vao];
            }
        }

        for(GSChunkVAO *vao in vaosToRemove)
        {
            [_drawList removeObject:vao];
        }
    }

    // Second, add VAOs to the list where possible. Do not block. We'll miss a bunch, but that's OK because we'll pick
    // those up eventually and will never let them go until the chunks exit the camera frustum.
    [self _unlockedConstructDrawList];

    // Third, draw them.
    for(GSChunkVAO *vao in _drawList)
    {
        [vao draw];
    }
    
    [_lockDrawList unlock];

#if LOG_PERF
    uint64_t elapsedTotal = stopwatchEnd(startAbs);
    NSLog(@"draw: %.3f ms (count=%lu)",
          (float)elapsedTotal / (float)NSEC_PER_MSEC,
          (unsigned long)_drawList.count);
#endif
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
        vector_float3 p1 = (vector_float3){center.x + p.x*CHUNK_SIZE_X, p.y*CHUNK_SIZE_Y, center.z + p.z*CHUNK_SIZE_Z};
        vector_float3 centerP = (vector_float3){floorf(p1.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                                                floorf(p1.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                                                floorf(p1.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2};
        int result = chunkInFrustum(frustum, centerP);
        if(GSFrustumOutside != result) {
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

- (void)modifyWithGroup:(nonnull dispatch_group_t)group
                  block:(NSArray<GSBoxedVector *> * _Nonnull (^ _Nonnull)(dispatch_group_t _Nonnull group))block
{
    [_lockDrawList lock];
    [_drawList removeAllObjects];

    // The block is expected to modify some part of the active region and return a list of points which had changes.
    // Some activity such as chunk invalidation is performed asynchronously and each block is added to the specified
    // dispatch group.
    NSArray<GSBoxedVector *> *points = block(group);

    // Wait for blocks in the group to complete. Once finished, all chunk invalidation will have been completed.
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Do synchronous chunk generation for the chunks which were modified.
    for(GSBoxedVector *boxedPosition in points)
    {
        dispatch_async(_generationQueue, ^{
            [_gridVAO objectAtPoint:[boxedPosition vectorValue]
                           blocking:YES
                             object:nil
                    createIfMissing:YES];
        });
    }
    
    dispatch_barrier_sync(_generationQueue, ^{});

    // And then build a new draw list for the display link thread.
    [self _unlockedConstructDrawList];
    
    [_lockDrawList unlock];
}

- (void)needsChunkGeneration
{
    if (self.shouldShutdown) {
        return;
    }

    dispatch_async(_generationQueue, ^{
        BOOL anyChunksMissing = NO;
        uint64_t startAbs = stopwatchStart();

        [_lockCachedPointsInCameraFrustum lockForReading];
        NSObject<NSFastEnumeration> *points = [_cachedPointsInCameraFrustum copy];
        [_lockCachedPointsInCameraFrustum unlockForReading];

        for(GSBoxedVector *boxedPosition in points)
        {
            uint64_t elapsedNs = stopwatchEnd(startAbs);
            BOOL createIfMissing = elapsedNs < GSChunkCreationBudget;
            BOOL r = [_gridVAO objectAtPoint:[boxedPosition vectorValue]
                                    blocking:YES
                                      object:nil
                             createIfMissing:createIfMissing];
            
            anyChunksMissing = anyChunksMissing && r;
        }
        
        if (anyChunksMissing) {
            [self needsChunkGeneration]; // Pick this up again later.
        }
    });
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    NSArray<GSBoxedVector *> *points = [self pointsInCameraFrustum];
    [_lockCachedPointsInCameraFrustum lockForWriting];
    _cachedPointsInCameraFrustum = points;
    [_lockCachedPointsInCameraFrustum unlockForWriting];
}

- (void)shutdown
{
    self.shouldShutdown = YES;

    dispatch_barrier_sync(_generationQueue, ^{}); // flush

    [_lockDrawList lock];
    [_drawList removeAllObjects];
    [_lockDrawList unlock];
}

@end
