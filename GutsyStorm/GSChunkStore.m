//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <OpenGL/glu.h>
#import <assert.h>
#import <cache.h>
#import "GSRay.h"
#import "GSBoxedRay.h"
#import "GSBoxedVector.h"
#import "GSChunkStore.h"
#import "GSNoise.h"

static float groundGradient(float terrainHeight, GSVector3 p);
static void generateTerrainVoxel(unsigned seed, float terrainHeight, GSVector3 p, voxel_t *outVoxel);


@interface GSChunkStore (Private)

- (voxel_t)getVoxelAtPointNoLock:(GSVector3)pos;
+ (NSURL *)newWorldSaveFolderURLWithSeed:(unsigned)seed;
- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (GSVector3)computeChunkCenterForPoint:(GSVector3)p;
- (chunk_id_t)getChunkIDWithMinP:(GSVector3)minP;
- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock;
- (void)computeChunkVisibility;
- (void)computeActiveChunks:(BOOL)sorted;
- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags;
- (NSArray *)sortPointsByDistFromCamera:(NSMutableArray *)unsortedPoints;
- (NSArray *)sortChunksByDistFromCamera:(NSMutableArray *)unsortedChunks;
- (GSNeighborhood *)neighborhoodAtPoint:(GSVector3)p;
- (GSChunkGeometryData *)getChunkGeometryAtPoint:(GSVector3)p;
- (GSChunkVoxelData *)getChunkVoxelsAtPoint:(GSVector3)p;
- (void)rebuildIndirectSunlightAndGeometryAround:(GSVector3)pos;

@end


@implementation GSChunkStore

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if(![defaults objectForKey:@"ActiveRegionExtent"]) {
        NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:@"256", @"ActiveRegionExtent", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    if(![defaults objectForKey:@"NumVBOGenerationsAllowedPerFrame"]) {
        NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:@"64", @"NumVBOGenerationsAllowedPerFrame", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
         glContext:(NSOpenGLContext *)_glContext
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
        terrainHeight = 40.0;
        folder = [GSChunkStore newWorldSaveFolderURLWithSeed:seed];
        groupForSaving = dispatch_group_create();
        
        camera = _camera;
        [camera retain];
        oldCenterChunkID = [self getChunkIDWithMinP:[self computeChunkMinPForPoint:[camera cameraEye]]];
        [oldCenterChunkID retain];
        
        terrainShader = _terrainShader;
        [terrainShader retain];
        
        glContext = _glContext;
        [glContext retain];
        
        lock = [[NSLock alloc] init];
        
        /* VBO generation must be performed on the main thread.
         * To preserve responsiveness, limit the number of VBOs we create per frame.
         */
        NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"NumVBOGenerationsAllowedPerFrame"];
        assert(n > 0 && n < INT_MAX);
        numVBOGenerationsAllowedPerFrame = (int)n;
        
        timeBetweenlIndirectSunlightUpdates = 2;
        timeUntilIndirectSunlightUpdate = timeBetweenlIndirectSunlightUpdates;
        
        /* Why are we specfying the background-priority global dispatch queue here?
         *
         * Answer:
         * My use of locks does not work well with libdispatch. Neither does the way I'm handling the loading of chunks from disk.
         * When a dispatch block blocks the thread its running on, libdispatch will create a new thread to begin execution of the
         * next block in the queue (up to a limit). Because I'm using locks all over the place, I cause many, many new threads to be
         * created. These put too much load on the system, and cause the main thread to get less execution time; frame deadlines are
         * missed, and FPS drops. These threads eventually quiet down as computation to generate/load the active region is
         * completed. So, eventually, the "warm up" period ends, and FPS jumps up to a steady 60.
         *
         * The threads that execute blocks on background queue run with a less favorable scheduling priority, allowing the main
         * thread to meet its deadlines. They also run with I/O throttling per setpriority(2) and so is not a good long-term
         * solution.
         */
        chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        // Active region is bounded at y>=0.
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
        activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:GSVector3_Make(w, CHUNK_SIZE_Y, w)];
        
        lockGeometryData = [[NSLock alloc] init];
        cacheGeometryData = [[NSCache alloc] init];
        [cacheGeometryData setCountLimit:INT_MAX];
        
        lockVoxelData = [[NSLock alloc] init];
        cacheVoxelData = [[NSCache alloc] init];
        [cacheVoxelData setCountLimit:INT_MAX];
        
        // Do a full refresh.
        [self computeActiveChunks:YES];
        [self computeChunkVisibility];
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
    
    [lockVoxelData release];
    [cacheVoxelData release];
    [lockGeometryData release];
    [cacheGeometryData release];
    [camera release];
    [folder release];
    [terrainShader release];
    [glContext release];
    [lock release];
    [activeRegion release];
    dispatch_release(chunkTaskQueue);
    
    [super dealloc];
}


- (void)drawChunks
{   
    [terrainShader bind];
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    
    glTranslatef(0.5, 0.5, 0.5);
    
    __block int numVBOGenerationsRemaining = numVBOGenerationsAllowedPerFrame;
    [activeRegion forEachChunkDoBlock:^(GSChunkGeometryData *chunk) {
        if(chunk && chunk->visible && [chunk drawGeneratingVBOsIfNecessary:(numVBOGenerationsRemaining > 0)]) {
            numVBOGenerationsRemaining--;
        }
    }];
    
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    
    [terrainShader unbind];
}


- (NSMutableArray *)newListOfPointsWithOutOfDateIndirectSunlightAndFilterVisible:(BOOL)filter
{
    NSMutableArray *points = [[NSMutableArray alloc] init];
    
    // Get the list of out-of-date chunks that are currently visible.
    [self enumeratePointsInActiveRegionUsingBlock:^(GSVector3 p) {
        if(filter) {
            GSChunkVoxelData *voxels = [self getChunkVoxelsAtPoint:p];
            GSChunkGeometryData *geometry = [self getChunkGeometryAtPoint:p];
            if(geometry->visible && voxels.indirectSunlightIsOutOfDate) {
                [points addObject:[GSBoxedVector boxedVectorWithVector:voxels.centerP]];
            }
        } else {
            GSChunkVoxelData *voxels = [self getChunkVoxelsAtPoint:p];
            if(voxels.indirectSunlightIsOutOfDate) {
                [points addObject:[GSBoxedVector boxedVectorWithVector:voxels.centerP]];
            }
        }
    }];
    
    return points;
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
    [self recalculateActiveChunksWithCameraModifiedFlags:flags];
    
    // Periodically rebuild chunks' out-of-date indirect sunlight and all associated geometry.
    timeUntilIndirectSunlightUpdate -= dt;
    if(timeUntilIndirectSunlightUpdate <= 0) {
        timeUntilIndirectSunlightUpdate = timeBetweenlIndirectSunlightUpdates;
        
        dispatch_async(chunkTaskQueue, ^{
            // We want to prioritize chunks that are visible.
            NSArray *points = [self newListOfPointsWithOutOfDateIndirectSunlightAndFilterVisible:YES];
            if([points count] == 0) {
                // Fallback to updating non-visible chunks.
                [points release];
                points = [self newListOfPointsWithOutOfDateIndirectSunlightAndFilterVisible:NO];
            }
            
            // Rebuild one chunk, chosen randomly from the list.
            if([points count] > 0) {
                NSLog(@"Rebuilding indirect sunlight for a chunk.");
                NSUInteger n = rand() % [points count];
                [self rebuildIndirectSunlightAndGeometryAround:[[points objectAtIndex:n] vectorValue]];
            }
            
            [points release];
        });
    }
}


- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)newBlock
{
    [lock lock];

    // Modify the voxel itself.
    {
        GSChunkVoxelData *chunk = [self getChunkVoxelsAtPoint:pos];
        
        [chunk writerAccessToVoxelDataUsingBlock:^{
            GSVector3 chunkLocalP;
            voxel_t *block;
            
            chunkLocalP = GSVector3_Sub(pos, chunk.minP);
            
            block = [chunk getPointerToVoxelAtPoint:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];
            assert(block);
            
            *block = newBlock;
            
            [chunk voxelDataWasModified];
        }];
    }
    
    [self rebuildIndirectSunlightAndGeometryAround:pos];
    
    [lock unlock];
}


- (voxel_t)getVoxelAtPoint:(GSVector3)pos
{
    voxel_t voxel;
    [lock lock];
    voxel = [self getVoxelAtPointNoLock:pos];
    [lock unlock];
    
    return voxel;
}


/* Get the distance to the first intersection of the ray with a solid block.
 * A distance before the intersection will be returned in outDistanceBefore.
 * A distance after the intersection will be returned in outDistanceAfter.
 * Will not look farther than maxDist.
 * Returns YES if an intersection could be found, false otherwise.
 */
- (BOOL)getPositionOfBlockAlongRay:(GSRay)ray
                           maxDist:(float)maxDist
                  outDistanceBefore:(float *)outDistanceBefore
                  outDistanceAfter:(float *)outDistanceAfter
{
    [lock lock];
    
    assert(maxDist > 0);
    
    const size_t MAX_PASSES = 6;
    const float step[MAX_PASSES] = {1.0f, 0.1f, 0.01f, 0.001f, 0.0001f, 0.00001f};
    
    BOOL foundAnything = NO;
    float d = 0, prevD = 0;
    
    for(size_t i = 0; i < MAX_PASSES; ++i)
    {
        // Sweep forward to find the intersection point.
        for(d = prevD; d < maxDist; d += step[i])
        {
            GSVector3 pos = GSVector3_Add(ray.origin, GSVector3_Scale(GSVector3_Normalize(ray.direction), d));
            
            // world does not extend below y=0
            if(pos.y < 0) {
                [lock unlock];
                return NO;
            }
            
            // world does not extend below y=activeRegionExtent.y
            if(pos.y >= activeRegion.activeRegionExtent.y) {
                [lock unlock];
                return NO;
            }
            
            voxel_t block = [self getVoxelAtPointNoLock:pos];
            
            if(!isVoxelEmpty(block)) {
                foundAnything = YES;
                break;
            }
            
            prevD = d;
        }
        
        if(!foundAnything) {
            [lock unlock];
            return NO;
        }
    }
    
    if(outDistanceBefore) {
        *outDistanceBefore = prevD;
    }
    
    if(outDistanceAfter) {
        *outDistanceAfter = d;
    }
    
    [lock unlock];
    return YES;
}

@end


@implementation GSChunkStore (Private)

- (voxel_t)getVoxelAtPointNoLock:(GSVector3)pos
{
    __block voxel_t block;
    GSChunkVoxelData *chunk = [self getChunkVoxelsAtPoint:pos];

    [chunk readerAccessToVoxelDataUsingBlock:^{
        GSVector3 chunkLocalP = GSVector3_Sub(pos, chunk.minP);
        block = [chunk getVoxelAtPoint:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];
    }];
    
    return block;
}


- (GSChunkGeometryData *)getChunkGeometryAtPoint:(GSVector3)p
{
    [lockGeometryData lock];
    
    GSChunkGeometryData *geometry = nil;
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    chunk_id_t chunkID = [self getChunkIDWithMinP:minP];
    
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegion.activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    geometry = [cacheGeometryData objectForKey:chunkID];
    if(!geometry) {
        GSNeighborhood *neighborhood = [self neighborhoodAtPoint:p];

        // This will initially have no indirect sunlight applied to it. We generate that later and update geometry when its ready.
        geometry = [[[GSChunkGeometryData alloc] initWithMinP:minP
                                                    voxelData:neighborhood
                                               chunkTaskQueue:chunkTaskQueue
                                                    glContext:glContext] autorelease];
        
        [cacheGeometryData setObject:geometry forKey:chunkID];
    }
    
    [lockGeometryData unlock];
    
    return geometry;
}


- (GSNeighborhood *)neighborhoodAtPoint:(GSVector3)p
{
    GSNeighborhood *neighborhood = [[[GSNeighborhood alloc] init] autorelease];
    
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSVector3 a = GSVector3_Add(p, [GSNeighborhood getOffsetForNeighborIndex:i]);
        [neighborhood setNeighborAtIndex:i neighbor:[self getChunkVoxelsAtPoint:a]];
    }
    
    return neighborhood;
}


- (GSChunkVoxelData *)getChunkVoxelsAtPoint:(GSVector3)p
{
    [lockVoxelData lock];
    
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    chunk_id_t chunkID = [self getChunkIDWithMinP:minP];
    
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegion.activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkVoxelData *voxels = [cacheVoxelData objectForKey:chunkID];
    if(!voxels) {
        voxels = [[GSChunkVoxelData alloc] initWithMinP:minP
                                                 folder:folder
                                         groupForSaving:groupForSaving
                                         chunkTaskQueue:chunkTaskQueue
                                              generator:^(GSVector3 p, voxel_t *voxel) {
                                                  generateTerrainVoxel(seed, terrainHeight, p, voxel);
                                              }];
        [voxels autorelease];
        [cacheVoxelData setObject:voxels forKey:chunkID];
    }
    
    [lockVoxelData unlock];
    
    return voxels;
}


- (NSArray *)sortChunksByDistFromCamera:(NSMutableArray *)unsortedChunks
{    
    GSVector3 cameraEye = [camera cameraEye];
    
    NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(id a, id b) {
        GSChunkData *chunkA = (GSChunkData *)a;
        GSChunkData *chunkB = (GSChunkData *)b;
        GSVector3 centerA = GSVector3_Scale(GSVector3_Add([chunkA minP], [chunkA maxP]), 0.5);
        GSVector3 centerB = GSVector3_Scale(GSVector3_Add([chunkB minP], [chunkB maxP]), 0.5);
        float distA = GSVector3_Length(GSVector3_Sub(centerA, cameraEye));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, cameraEye));;
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
    
    return sortedChunks;
}


- (NSArray *)sortPointsByDistFromCamera:(NSMutableArray *)unsortedPoints
{
    GSVector3 center = [camera cameraEye];
    
    return [unsortedPoints sortedArrayUsingComparator: ^(id a, id b) {
        GSVector3 centerA = [(GSBoxedVector *)a vectorValue];
        GSVector3 centerB = [(GSBoxedVector *)b vectorValue];
        float distA = GSVector3_Length(GSVector3_Sub(centerA, center));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, center));
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
}


+ (NSURL *)newWorldSaveFolderURLWithSeed:(unsigned)seed
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    folder = [folder stringByAppendingPathComponent:@"GutsyStorm"];
    folder = [folder stringByAppendingPathComponent:@"save"];
    folder = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",seed]];
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

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}


- (GSVector3)computeChunkCenterForPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
}


- (chunk_id_t)getChunkIDWithMinP:(GSVector3)minP
{
    return [[[GSBoxedVector alloc] initWithVector:minP] autorelease];
}


- (void)computeChunkVisibility
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();

    GSFrustum *frustum = [camera frustum];
    
    [activeRegion forEachChunkDoBlock:^(GSChunkGeometryData *geometry) {
        geometry->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:geometry->corners]);
    }];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock
{
    const GSVector3 center = [camera cameraEye];
    const GSVector3 activeRegionExtent = activeRegion.activeRegionExtent;
    const ssize_t activeRegionExtentX = activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = activeRegionExtent.y/CHUNK_SIZE_Y;

    for(ssize_t x = -activeRegionExtentX; x < activeRegionExtentX; ++x)
    {
        for(ssize_t y = 0; y < activeRegionSizeY; ++y)
        {
            for(ssize_t z = -activeRegionExtentZ; z < activeRegionExtentZ; ++z)
            {
                assert((x+activeRegionExtentX) >= 0);
                assert(x < activeRegionExtentX);
                assert((z+activeRegionExtentZ) >= 0);
                assert(z < activeRegionExtentZ);
                assert(y >= 0);
                assert(y < activeRegionSizeY);
                
                GSVector3 p1 = GSVector3_Make(center.x + x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, center.z + z*CHUNK_SIZE_Z);
                
                GSVector3 p2 = [self computeChunkCenterForPoint:p1];
                
                myBlock(p2);
            }
        }
    }
}


// Compute active chunks. If sorted then take the time to ensure NEAR chunks come in before FAR chunks.
- (void)computeActiveChunks:(BOOL)sorted
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    /* Copy the activeChunks array to retain all chunks. This prevents chunks from being deallocated when we are in the process of
     * selecting the new set of active chunks. This, in turn, can prevent eviction of chunks which were in the active region and
     * will remain in the active region.
     * Also, reset visibility computation on all active chunks. We'll recalculate a bit later.
     */
    NSMutableArray *tmpActiveChunks = [[NSMutableArray alloc] initWithCapacity:activeRegion.maxActiveChunks];
    
    [activeRegion forEachChunkDoBlock:^(GSChunkGeometryData *geometry) {
        if(geometry) {
            geometry->visible = NO;
            [tmpActiveChunks addObject:geometry];
        }
    }];
    
    [activeRegion removeAllActiveChunks];
    
    if(sorted) {
        NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
        
        [self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
            GSBoxedVector *b = [[GSBoxedVector alloc] initWithVector:p];
            [unsortedChunks addObject:b];
            [b release];
        }];
        
        // Sort by distance from the camera. Near chunks are first.
        NSArray *sortedChunks = [self sortPointsByDistFromCamera:unsortedChunks]; // is autorelease
        
        // Fill the activeChunks array.
        NSUInteger i = 0;
        for(GSBoxedVector *b in sortedChunks)
        {
            [activeRegion setActiveChunk:[self getChunkGeometryAtPoint:[b vectorValue]] atIndex:i];
            i++;
        }
        assert(i == activeRegion.maxActiveChunks);
        
        [unsortedChunks release];
    } else {
        __block NSUInteger i = 0;
        [self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
            [activeRegion setActiveChunk:[self getChunkGeometryAtPoint:p] atIndex:i];
            i++;
        }];
        assert(i == activeRegion.maxActiveChunks);
    }
    
    /* Now release all the chunks in tmpActiveChunks. Chunks which remain in the
     * active region have the same refcount as when we started the update. Chunks
     * which left the active region are released entirely.
     */
    [tmpActiveChunks release];
    
    // Clean up
    [pool release];
}


- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
    // If the camera moved then recalculate the set of active chunks.
    if(flags & CAMERA_MOVED) {
        // We can avoid a lot of work if the camera hasn't moved enough to add/remove any chunks in the active region.
        chunk_id_t newCenterChunkID = [self getChunkIDWithMinP:[self computeChunkMinPForPoint:[camera cameraEye]]];
        
        if(![oldCenterChunkID isEqual:newCenterChunkID]) {
            [self computeActiveChunks:NO];
            
            // Now save this chunk ID for comparison next update.
            [oldCenterChunkID release];
            oldCenterChunkID = newCenterChunkID;
            [oldCenterChunkID retain];
        }
    }
    
    // If the camera moved or turned then recalculate chunk visibility.
    if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        [self computeChunkVisibility];
    }
}


- (void)rebuildIndirectSunlightAndGeometryAround:(GSVector3)pos
{
    /* In order to correctly handle the case where indirect sunlight is removed (say, by sealing a hole) indirect sunlight must be
     * regenerated from scratch for all chunks in the neighborhood. There's no need to attempt to propagate the effect out further
     * than that because the light radius is always less than the width of a single chunk.
     */

    dispatch_async(chunkTaskQueue, ^{
        NSMutableSet *dirtyMeshes = [[NSMutableSet alloc] init];
        
        GSNeighborhood *neighborhood = [self neighborhoodAtPoint:pos];
        
        [neighborhood forEachNeighbor:^(GSChunkVoxelData *voxels) {
            GSNeighborhood *innerNeighborhood = [self neighborhoodAtPoint:voxels.centerP];
            
            [voxels rebuildIndirectSunlightWithNeighborhood:innerNeighborhood
                                          completionHandler:^{
                                              [dirtyMeshes addObject:[GSBoxedVector boxedVectorWithVector:voxels.centerP]];
                                          }];
        }];
        
        // Rebuild geometry where indirect sunlight was updated.
        for(GSBoxedVector *b in dirtyMeshes)
        {
            GSVector3 p = [b vectorValue];
            
            dispatch_async(chunkTaskQueue, ^{
                GSNeighborhood *neighborhood = [self neighborhoodAtPoint:p];
                
                [neighborhood forEachNeighbor:^(GSChunkVoxelData *voxels) {
                    [lock lock];
                    GSNeighborhood *voxelsNeighborhood = [self neighborhoodAtPoint:voxels.centerP];
                    GSChunkGeometryData *geometry = [self getChunkGeometryAtPoint:voxels.centerP];
                    [lock unlock];
                    
                    [geometry updateWithVoxelData:voxelsNeighborhood];
                }];
            });
        }
        
        [dirtyMeshes release];
    });
   
}

@end


// Return a value between -1 and +1 so that a line through the y-axis maps to a smooth gradient of values from -1 to +1.
static float groundGradient(float terrainHeight, GSVector3 p)
{
    const float y = p.y;
    
    if(y < 0.0) {
        return -1;
    } else if(y > terrainHeight) {
        return +1;
    } else {
        return 2.0*(y/terrainHeight) - 1.0;
    }
}


// Generates a voxel for the specified point in space. Returns that voxel in `outVoxel'.
static void generateTerrainVoxel(unsigned seed, float terrainHeight, GSVector3 p, voxel_t *outVoxel)
{
    static dispatch_once_t onceToken;
    static GSNoise *noiseSource0;
    static GSNoise *noiseSource1;
    
    BOOL groundLayer = NO;
    BOOL floatingMountain = NO;
    
    assert(outVoxel);
    
    dispatch_once(&onceToken, ^{
        noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
        noiseSource1 = [[GSNoise alloc] initWithSeed:seed+1];
    });
    
    // Normal rolling hills
    {
        const float freqScale = 0.025;
        float n = [noiseSource0 getNoiseAtPointWithFourOctaves:GSVector3_Scale(p, freqScale)];
        float turbScaleX = 2.0;
        float turbScaleY = terrainHeight / 2.0;
        float yFreq = turbScaleX * ((n+1) / 2.0);
        float t = turbScaleY * [noiseSource1 getNoiseAtPoint:GSVector3_Make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
        groundLayer = groundGradient(terrainHeight, GSVector3_Make(p.x, p.y + t, p.z)) <= 0;
    }
    
    // Giant floating mountain
    {
        /* The floating mountain is generated by starting with a sphere and applying turbulence to the surface.
         * The upper hemisphere is also squashed to make the top flatter.
         */
        
        GSVector3 mountainCenter = GSVector3_Make(50, 50, 80);
        GSVector3 toMountainCenter = GSVector3_Sub(mountainCenter, p);
        float distance = GSVector3_Length(toMountainCenter);
        float radius = 30.0;
        
        // Apply turbulence to the surface of the mountain.
        float freqScale = 0.70;
        float turbScale = 15.0;
        
        // Avoid generating noise when too far away from the center to matter.
        if(distance > 2.0*radius) {
            floatingMountain = NO;
        } else {
            // Convert the point into spherical coordinates relative to the center of the mountain.
            float azimuthalAngle = acosf(toMountainCenter.z / distance);
            float polarAngle = atan2f(toMountainCenter.y, toMountainCenter.x);
            
            float t = turbScale * [noiseSource0 getNoiseAtPointWithFourOctaves:GSVector3_Make(azimuthalAngle * freqScale,
                                                                                              polarAngle * freqScale, 0.0)];
            
            // Flatten the top.
            if(p.y > mountainCenter.y) {
                radius -= (p.y - mountainCenter.y) * 3;
            }
            
            floatingMountain = (distance+t) < radius;
        }
    }
    
    *outVoxel = (groundLayer || floatingMountain) ? ~VOXEL_EMPTY : VOXEL_EMPTY;
}