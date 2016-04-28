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
#import "GSChunkStore.h"
#import "GSChunkVAO.h"
#import "GSActivity.h"
#import "GSReaderWriterLock.h"


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
    __weak GSChunkStore *_chunkStore;

    /* Dispatch Queue used for generating chunks asynchronously. */
    dispatch_queue_t _generationQueue;
    
    /* Semaphore used to prevent the generation queue from having too many outstanding chunks. */
    dispatch_semaphore_t _generationSema;
    
    /* List of VAOs the display link thread will draw. */
    NSMutableSet<GSChunkVAO *> *_drawList;
    NSLock *_lockDrawList;
    
    /* The calculated set of chunk points in the camera frustum. */
    NSArray<GSBoxedVector *> *_cachedPointsInCameraFrustum;
    GSReaderWriterLock *_lockCachedPointsInCameraFrustum;
}

- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                            camera:(nonnull GSCamera *)camera
                                        chunkStore:(nonnull GSChunkStore *)chunkStore
{
    NSParameterAssert(camera);
    NSParameterAssert(chunkStore);
    NSParameterAssert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
    NSParameterAssert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
    NSParameterAssert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

    if (self = [super init]) {
        _shouldShutdown = NO;
        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _chunkStore = chunkStore;
        _generationQueue = dispatch_queue_create("GSActiveRegion.generationQueue", DISPATCH_QUEUE_CONCURRENT);
        
        long n = [[NSProcessInfo processInfo] processorCount];
        _generationSema = dispatch_semaphore_create(n);

        _drawList = [NSMutableSet new];
        _lockDrawList = [NSLock new];
        _lockDrawList.name = @"GSActiveRegion.lockDrawList";
        
        _cachedPointsInCameraFrustum = nil;
        _lockCachedPointsInCameraFrustum = [GSReaderWriterLock new];
        _lockCachedPointsInCameraFrustum.name = @"GSActiveRegion.lockCachedPointsInCameraFrustum";
    }
    
    return self;
}

- (void)draw
{
    BOOL chunkGenerationNeeded = NO;

    if (self.shouldShutdown) {
        return;
    }
    
    //GSStopwatchTraceBegin(@"GSActiveRegion.draw");

    [_lockDrawList lock];

    NSMutableArray<GSChunkVAO *> *vaosToRemove = [NSMutableArray new];

    // Mark the VAOs which are no longer in the camera frustum for removal.
    for(GSChunkVAO *vao in _drawList)
    {
        if(GSFrustumOutside == chunkInFrustum(_camera.frustum, vao.minP)) {
            [vaosToRemove addObject:vao];
        }
    }
    GSStopwatchTraceStep(@"Finished checking VAOs against camera frustum.");
    
    // Keep a dictionary to map from minP to VAO in constant-time.
    NSMutableDictionary *pointToChunk = [NSMutableDictionary new];
    for(GSChunkVAO *vao in _drawList)
    {
        GSBoxedVector *point = [GSBoxedVector boxedVectorWithVector:vao.minP];
        pointToChunk[point] = vao;
    }
    
    // Iterate over points in the camera frustum. If we can get a new VAO for a point then use the new VAO and remove
    // the reference to the old VAO. If we can't get a new one then keep using the old VAO.
    [_lockCachedPointsInCameraFrustum lockForReading];
    NSObject<NSFastEnumeration> *points = [_cachedPointsInCameraFrustum copy];
    [_lockCachedPointsInCameraFrustum unlockForReading];

    for(GSBoxedVector *boxedPosition in points)
    {
        vector_float3 pos = [boxedPosition vectorValue];
        GSBoxedVector *corner = [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(pos)];
        GSChunkVAO *oldVao = [pointToChunk objectForKey:corner];
        GSChunkVAO *vao = [_chunkStore tryToGetVaoAtPoint:pos];

        if (vao) {
            if (oldVao != vao) {
                [_drawList addObject:vao];
                
                if (oldVao) {
                    [vaosToRemove addObject:oldVao];
                }
            }
        } else {
            chunkGenerationNeeded = YES;
        }
    }
    
    // Now remove those chunks which were marked for removal earlier.
    for(GSChunkVAO *vao in vaosToRemove)
    {
        [_drawList removeObject:vao];
    }
    GSStopwatchTraceStep(@"Finished building draw list.");

    // Draw them all.
    for(GSChunkVAO *vao in _drawList)
    {
        [vao draw];
    }
    GSStopwatchTraceStep(@"Finished drawing VAOs.");
    
    [_lockDrawList unlock];
    
    if (chunkGenerationNeeded) {
        [self needsChunkGeneration];
    }
    
    //GSStopwatchTraceEnd(@"GSActiveRegion.draw");
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

- (void)needsChunkGeneration
{
    if (self.shouldShutdown) {
        return;
    }
    
    if (dispatch_semaphore_wait(_generationSema, DISPATCH_TIME_NOW)) {
        // Drop the request on the floor because we don't want the queue to have too many outstanding chunks.
        return;
    }

    dispatch_async(_generationQueue, ^{
        BOOL anyChunksMissing = NO;
        uint64_t startAbs = GSStopwatchStart();

        [_lockCachedPointsInCameraFrustum lockForReading];
        NSObject<NSFastEnumeration> *points = [_cachedPointsInCameraFrustum copy];
        [_lockCachedPointsInCameraFrustum unlockForReading];

        for(GSBoxedVector *position in points)
        {
            // Ensure VAO gets created, if it was missing.
            (void)[_chunkStore nonBlockingVaoAtPoint:position createIfMissing:YES];

            uint64_t elapsedNs = GSStopwatchEnd(startAbs);
            
            if (elapsedNs > GSChunkCreationBudget) {
                anyChunksMissing = YES;
                break;
            }
        }

        if (anyChunksMissing) {
            [self needsChunkGeneration]; // Pick this up again later.
        }
        
        dispatch_semaphore_signal(_generationSema);
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
