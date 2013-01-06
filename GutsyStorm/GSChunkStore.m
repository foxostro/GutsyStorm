//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSRay.h"
#import "GSChunkGeometryData.h"
#import "GSCamera.h"
#import "GSGrid.h"
#import "GSActiveRegion.h"
#import "GSShader.h"
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

+ (NSURL *)newWorldSaveFolderURLWithSeed:(NSUInteger)seed;
- (void)updateChunkVisibilityForActiveRegion;
- (void)updateActiveChunksWithCameraModifiedFlags:(unsigned)flags;
- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p;
- (BOOL)tryToGetNeighborhoodAtPoint:(GLKVector3)p neighborhood:(GSNeighborhood **)neighborhood;
- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p;
- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p;
- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk;
- (id)newChunkWithMinimumCorner:(GLKVector3)minP;

@end


@implementation GSChunkStore
{
    GSGrid *gridVoxelData;
    GSGrid *gridGeometryData;

    dispatch_group_t groupForSaving;
    dispatch_queue_t chunkTaskQueue;

    NSLock *lock;
    NSUInteger numVBOGenerationsAllowedPerFrame;
    GSCamera *camera;
    chunk_id_t oldCenterChunkID;
    NSURL *folder;
    GSShader *terrainShader;
    NSOpenGLContext *glContext;

    terrain_generator_t generator;
    terrain_post_processor_t postProcessor;

    GSActiveRegion *activeRegion;
    GLKVector3 activeRegionExtent; // The active region is specified relative to the camera position.
    int needsChunkVisibilityUpdate;

    float timeUntilNextPeriodicChunkUpdate;
    float timeBetweenPerioducChunkUpdates;
    int32_t activeRegionNeedsUpdate;
}

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if(![defaults objectForKey:@"ActiveRegionExtent"]) {
        NSDictionary *values = @{@"ActiveRegionExtent": @"256"};
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    if(![defaults objectForKey:@"NumVBOGenerationsAllowedPerFrame"]) {
        NSDictionary *values = @{@"NumVBOGenerationsAllowedPerFrame": @"64"};
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (id)initWithSeed:(NSUInteger)seed
            camera:(GSCamera *)_camera
       terrainShader:(GSShader *)_terrainShader
           glContext:(NSOpenGLContext *)_glContext
           generator:(terrain_generator_t)_generator
       postProcessor:(terrain_post_processor_t)_postProcessor
{
    self = [super init];
    if (self) {
        folder = [GSChunkStore newWorldSaveFolderURLWithSeed:seed];
        groupForSaving = dispatch_group_create();
        
        camera = _camera;
        [camera retain];
        oldCenterChunkID = [GSChunkData chunkIDWithChunkMinCorner:[GSChunkData minCornerForChunkAtPoint:[camera cameraEye]]];
        [oldCenterChunkID retain];
        
        terrainShader = _terrainShader;
        [terrainShader retain];
        
        glContext = _glContext;
        [glContext retain];
        
        lock = [[NSLock alloc] init];
        
        timeUntilNextPeriodicChunkUpdate = 0.0;
        timeBetweenPerioducChunkUpdates = 1.0;
        activeRegionNeedsUpdate = 0;

        generator = [_generator copy];
        postProcessor = [_postProcessor copy];
        
        /* VBO generation must be performed on the main thread.
         * To preserve responsiveness, limit the number of VBOs we create per frame.
         */
        NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"NumVBOGenerationsAllowedPerFrame"];
        assert(n > 0 && n < INT_MAX);
        numVBOGenerationsAllowedPerFrame = (int)n;
        
        chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
        
        size_t areaXZ = (w/CHUNK_SIZE_X) * (w/CHUNK_SIZE_Z);
        gridGeometryData = [[GSGrid alloc] initWithActiveRegionArea:areaXZ];
        gridVoxelData = [[GSGrid alloc] initWithActiveRegionArea:areaXZ];
        
        // Do a full refresh fo the active region
        // Active region is bounded at y>=0.
        activeRegionExtent = GLKVector3Make(w, CHUNK_SIZE_Y, w);
        activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:activeRegionExtent];
        [activeRegion updateWithSorting:YES camera:camera chunkProducer:^GSChunkGeometryData *(GLKVector3 p) {
            return [self chunkGeometryAtPoint:p];
        }];
        needsChunkVisibilityUpdate = 1;
    }
    
    return self;
}


- (void)waitForSaveToFinish
{
    [lock lock];
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(groupForSaving, DISPATCH_TIME_FOREVER); // wait for save operations to complete
    NSLog(@"All chunks have been saved.");
    [lock unlock];
}


- (void)dealloc
{
    [self waitForSaveToFinish];
    dispatch_release(groupForSaving);
    
    [gridVoxelData release];
    [gridGeometryData release];
    [camera release];
    [folder release];
    [terrainShader release];
    [glContext release];
    [lock release];
    [activeRegion release];
    [generator release];
    [postProcessor release];
    dispatch_release(chunkTaskQueue);
    
    [super dealloc];
}


- (void)drawActiveChunks
{
    [terrainShader bind];

    glDisable(GL_CULL_FACE);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    
    glTranslatef(0.5, 0.5, 0.5);
    
    // Update chunk visibility flags now. We've been told it's necessary.
    if(OSAtomicCompareAndSwapIntBarrier(1, 0, &needsChunkVisibilityUpdate)) {
        [self updateChunkVisibilityForActiveRegion];
    }

    __block NSUInteger numVBOGenerationsRemaining = numVBOGenerationsAllowedPerFrame;
    [activeRegion enumerateActiveChunkWithBlock:^(GSChunkGeometryData *chunk) {
        assert(chunk);
        if(chunk.visible && [chunk drawGeneratingVBOsIfNecessary:(numVBOGenerationsRemaining>0)]) {
            numVBOGenerationsRemaining--;
        };
    }];
    
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);

    glEnable(GL_CULL_FACE);
    
    [terrainShader unbind];
}


// Try to update asynchronously dirty chunk sunlight. Skip any that would block due to lock contention.
- (void)tryToUpdateDirtySunlight
{
    void (^b)(GLKVector3) = ^(GLKVector3 p) {
        GSChunkVoxelData *voxels;

        // Avoid blocking to take the lock in GSGrid.
        if([self tryToGetChunkVoxelsAtPoint:p chunk:&voxels]) {
            dispatch_async(chunkTaskQueue, ^{
                if(!voxels.dirtySunlight) {
                    return;
                }

                GSNeighborhood *neighborhood = nil;
                if(![self tryToGetNeighborhoodAtPoint:voxels.centerP neighborhood:&neighborhood]) {
                    return;
                }
                
                [voxels tryToRebuildSunlightWithNeighborhood:neighborhood completionHandler:^{
                    GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:p];
                    geometry.dirty = YES;
                    [geometry tryToUpdateWithVoxelData:neighborhood]; // make an effort to update geometry immediately
                }];
            });
        }
    };
    
    [activeRegion enumeratePointsInActiveRegionNearCamera:camera usingBlock:b];
}


// Try to asynchronously update dirty chunk geometry. Skip any that would block due to lock contention.
- (void)tryToUpdateDirtyGeometry
{
    void (^b)(GSChunkGeometryData *) = ^(GSChunkGeometryData *geometry) {
        dispatch_async(chunkTaskQueue, ^{
            if(!geometry.dirty) {
                return;
            }

            GSNeighborhood *neighborhood = nil;
            if(![self tryToGetNeighborhoodAtPoint:geometry.centerP neighborhood:&neighborhood]) {
                return;
            }

            [geometry tryToUpdateWithVoxelData:neighborhood];
        });
    };
    
    [activeRegion enumerateActiveChunkWithBlock:b];
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
    timeUntilNextPeriodicChunkUpdate -= dt;
    if(timeUntilNextPeriodicChunkUpdate < 0) {
        timeBetweenPerioducChunkUpdates = timeBetweenPerioducChunkUpdates;
        
        dispatch_async(chunkTaskQueue, ^{
            [self tryToUpdateDirtySunlight];
            [self tryToUpdateDirtyGeometry];
        
            if(OSAtomicCompareAndSwap32Barrier(1, 0, &activeRegionNeedsUpdate)) {
                [self updateActiveChunksWithCameraModifiedFlags:(CAMERA_MOVED|CAMERA_TURNED)];
            }
        });
    }
    
    if((flags & CAMERA_MOVED) || (flags & CAMERA_TURNED)) {
        OSAtomicCompareAndSwap32Barrier(0, 1, &activeRegionNeedsUpdate);
    }
}


- (void)placeBlockAtPoint:(GLKVector3)pos block:(voxel_t)newBlock
{
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    [chunk writerAccessToVoxelDataUsingBlock:^{
        voxel_t *block = [chunk pointerToVoxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                                    pos.y-chunk.minP.y,
                                                                                    pos.z-chunk.minP.z)];
        assert(block);
        *block = newBlock;
    }];
    
    /* Invalidate sunlight data and geometry for the modified chunk and surrounding chunks.
     * Chunks' sunlight and geometry will be updated on the next update tick.
     */
    [[self neighborhoodAtPoint:pos] enumerateNeighborsWithBlock:^(GSChunkVoxelData *voxels) {
        voxels.dirtySunlight = YES;
        [self chunkGeometryAtPoint:voxels.centerP].dirty = YES;
    }];
}


- (BOOL)tryToGetVoxelAtPoint:(GLKVector3)pos voxel:(voxel_t *)voxel
{
    __block voxel_t block;
    GSChunkVoxelData *chunk;

    assert(voxel);

    if(![self tryToGetChunkVoxelsAtPoint:pos chunk:&chunk]) {
        return NO;
    }

    if(![chunk tryReaderAccessToVoxelDataUsingBlock:^{
        block = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                  pos.y-chunk.minP.y,
                                                                  pos.z-chunk.minP.z)];
    }]) {
        return NO;
    }

    *voxel = block;
    return YES;
}


- (voxel_t)voxelAtPoint:(GLKVector3)pos
{
    __block voxel_t block;
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    
    [chunk readerAccessToVoxelDataUsingBlock:^{
        block = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                  pos.y-chunk.minP.y,
                                                                  pos.z-chunk.minP.z)];
    }];
    
    return block;
}


- (BOOL)enumerateVoxelsOnRay:(GSRay)ray maxDepth:(unsigned)maxDepth withBlock:(void (^)(GLKVector3 p, BOOL *stop, BOOL *fail))block
{
    /* Implementation is based on:
     * "A Fast Voxel Traversal Algorithm for Ray Tracing"
     * John Amanatides, Andrew Woo
     * http://www.cse.yorku.ca/~amana/research/grid.pdf
     *
     * See also: http://www.xnawiki.com/index.php?title=Voxel_traversal
     */
    
    // NOTES:
    // * This code assumes that the ray's position and direction are in 'cell coordinates', which means
    //   that one unit equals one cell in all directions.
    // * When the ray doesn't start within the voxel grid, calculate the first position at which the
    //   ray could enter the grid. If it never enters the grid, there is nothing more to do here.
    // * Also, it is important to test when the ray exits the voxel grid when the grid isn't infinite.
    // * The Point3D structure is a simple structure having three integer fields (X, Y and Z).
    
    // The cell in which the ray starts.
    GSIntegerVector3 start = GSIntegerVector3_Make(floorf(ray.origin.x), floorf(ray.origin.y), floorf(ray.origin.z));
    int x = (int)start.x;
    int y = (int)start.y;
    int z = (int)start.z;
    
    // Determine which way we go.
    int stepX = (ray.direction.x<0) ? -1 : (ray.direction.x==0) ? 0 : +1;
    int stepY = (ray.direction.y<0) ? -1 : (ray.direction.y==0) ? 0 : +1;
    int stepZ = (ray.direction.z<0) ? -1 : (ray.direction.z==0) ? 0 : +1;
    
    // Calculate cell boundaries. When the step (i.e. direction sign) is positive,
    // the next boundary is AFTER our current position, meaning that we have to add 1.
    // Otherwise, it is BEFORE our current position, in which case we add nothing.
    GSIntegerVector3 cellBoundary = GSIntegerVector3_Make(x + (stepX > 0 ? 1 : 0),
                                                          y + (stepY > 0 ? 1 : 0),
                                                          z + (stepZ > 0 ? 1 : 0));
    
    // NOTE: For the following calculations, the result will be Single.PositiveInfinity
    // when ray.Direction.X, Y or Z equals zero, which is OK. However, when the left-hand
    // value of the division also equals zero, the result is Single.NaN, which is not OK.
    
    // Determine how far we can travel along the ray before we hit a voxel boundary.
    GLKVector3 tMax = GLKVector3Make((cellBoundary.x - ray.origin.x) / ray.direction.x,    // Boundary is a plane on the YZ axis.
                                    (cellBoundary.y - ray.origin.y) / ray.direction.y,    // Boundary is a plane on the XZ axis.
                                    (cellBoundary.z - ray.origin.z) / ray.direction.z);   // Boundary is a plane on the XY axis.
    if(isnan(tMax.x)) { tMax.x = +INFINITY; }
    if(isnan(tMax.y)) { tMax.y = +INFINITY; }
    if(isnan(tMax.z)) { tMax.z = +INFINITY; }

    // Determine how far we must travel along the ray before we have crossed a gridcell.
    GLKVector3 tDelta = GLKVector3Make(stepX / ray.direction.x,                    // Crossing the width of a cell.
                                      stepY / ray.direction.y,                    // Crossing the height of a cell.
                                      stepZ / ray.direction.z);                   // Crossing the depth of a cell.
    if(isnan(tDelta.x)) { tDelta.x = +INFINITY; }
    if(isnan(tDelta.y)) { tDelta.y = +INFINITY; }
    if(isnan(tDelta.z)) { tDelta.z = +INFINITY; }
    
    // For each step, determine which distance to the next voxel boundary is lowest (i.e.
    // which voxel boundary is nearest) and walk that way.
    for(int i = 0; i < maxDepth; i++)
    {
        if(y >= activeRegionExtent.y || y < 0) {
            return YES; // The vertical extent of the world is limited.
        }
        
        BOOL stop = NO;
        BOOL fail = NO;
        block(GLKVector3Make(x, y, z), &stop, &fail);

        if(fail) {
            return NO; // the block was going to block so it stopped and called for an abort
        }

        if(stop) {
            return YES;
        }
        
        // Do the next step.
        if (tMax.x < tMax.y && tMax.x < tMax.z) {
            // tMax.X is the lowest, an YZ cell boundary plane is nearest.
            x += stepX;
            tMax.x += tDelta.x;
        } else if (tMax.y < tMax.z) {
            // tMax.Y is the lowest, an XZ cell boundary plane is nearest.
            y += stepY;
            tMax.y += tDelta.y;
        } else {
            // tMax.Z is the lowest, an XY cell boundary plane is nearest.
            z += stepZ;
            tMax.z += tDelta.z;
        }
    }

    return YES;
}

@end


@implementation GSChunkStore (Private)

- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p
{
    GSNeighborhood *neighborhood = [[[GSNeighborhood alloc] init] autorelease];
    
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GLKVector3 a = GLKVector3Add(p, [GSNeighborhood offsetForNeighborIndex:i]);
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:a]; // NOTE: may block
        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }
    
    return neighborhood;
}


- (BOOL)tryToGetNeighborhoodAtPoint:(GLKVector3)p
                       neighborhood:(GSNeighborhood **)outNeighborhood
{
    assert(outNeighborhood);

    GSNeighborhood *neighborhood = [[[GSNeighborhood alloc] init] autorelease];

    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GLKVector3 a = GLKVector3Add(p, [GSNeighborhood offsetForNeighborIndex:i]);
        GSChunkVoxelData *voxels = nil;

        if(![self tryToGetChunkVoxelsAtPoint:a chunk:&voxels]) {
            return NO;
        }

        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }

    *outNeighborhood = neighborhood;
    return YES;
}


- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkGeometryData *g = [gridGeometryData objectAtPoint:p objectFactory:^id(GLKVector3 minP) {
        // Chunk geometry will be generated later and is only marked "dirty" for now.
        return [[[GSChunkGeometryData alloc] initWithMinP:minP
                                                   folder:folder
                                           groupForSaving:groupForSaving
                                           chunkTaskQueue:chunkTaskQueue
                                                glContext:glContext] autorelease];
    }];
    
    return g;
}


- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkVoxelData *v = [gridVoxelData objectAtPoint:p
                                         objectFactory:^id(GLKVector3 minP) {
                                             return [[self newChunkWithMinimumCorner:minP] autorelease];
                                         }];
    
    return v;
}


- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk
{
    BOOL success;
    GSChunkVoxelData *v;

    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    assert(chunk);

    success = [gridVoxelData tryToGetObjectAtPoint:p
                                            object:&v
                                     objectFactory:^id(GLKVector3 minP) {
                                         return [[self newChunkWithMinimumCorner:minP] autorelease];
                                     }];

    if(success) {
        *chunk = v;
        return YES;
    } else {
        return NO;
    }
}


+ (NSURL *)newWorldSaveFolderURLWithSeed:(NSUInteger)seed
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    
    folder = [folder stringByAppendingPathComponent:@"GutsyStorm"];
    folder = [folder stringByAppendingPathComponent:@"save"];
    folder = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu",seed]];
    NSLog(@"ChunkStore will save chunks to folder: %@", folder);
    
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        NSLog(@"Failed to create save folder: %@", folder);
    }
    
    NSURL *url = [[NSURL alloc] initFileURLWithPath:folder isDirectory:YES];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSLog(@"ChunkStore's Save folder not reachable: %@", folder);
    }
    
    return url;
}


- (void)updateChunkVisibilityForActiveRegion
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();

    GSFrustum *frustum = [camera frustum];
    
    [activeRegion enumerateActiveChunkWithBlock:^(GSChunkGeometryData *geometry) {
        // XXX: the GSChunkGeometryData could do this calculation itself...
        if(geometry) {
            geometry.visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:geometry.corners]);
        }
    }];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


- (void)updateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
    // If the camera moved then recalculate the set of active chunks.
    if(flags & CAMERA_MOVED) {
        // We can avoid a lot of work if the camera hasn't moved enough to add/remove any chunks in the active region.
        chunk_id_t newCenterChunkID = [GSChunkData chunkIDWithChunkMinCorner:[GSChunkData minCornerForChunkAtPoint:[camera cameraEye]]];
        
        if(![oldCenterChunkID isEqual:newCenterChunkID]) {
            [activeRegion updateWithSorting:NO camera:camera chunkProducer:^GSChunkGeometryData *(GLKVector3 p) {
                return [self chunkGeometryAtPoint:p];
            }];

            // Now save this chunk ID for comparison next update.
            [oldCenterChunkID release];
            oldCenterChunkID = newCenterChunkID;
            [oldCenterChunkID retain];
        }
    }
    
    // If the camera moved or turned then recalculate chunk visibility.
    if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        OSAtomicCompareAndSwapIntBarrier(0, 1, &needsChunkVisibilityUpdate);
    }
}

- (id)newChunkWithMinimumCorner:(GLKVector3)minP
{
    return [[GSChunkVoxelData alloc] initWithMinP:minP
                                           folder:folder
                                   groupForSaving:groupForSaving
                                   chunkTaskQueue:chunkTaskQueue
                                        generator:generator
                                    postProcessor:postProcessor];
}

@end