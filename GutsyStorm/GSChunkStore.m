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


@interface GSChunkStore (Private)

+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed;
- (void)deallocChunksWithArray:(GSChunkData **)array len:(size_t)len;
- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (GSVector3)computeChunkCenterForPoint:(GSVector3)p;
- (chunk_id_t)getChunkIDWithMinP:(GSVector3)minP;
- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock;
- (void)computeChunkVisibility;
- (void)computeActiveChunks:(BOOL)sorted;
- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags;
- (NSArray *)sortPointsByDistFromCamera:(NSMutableArray *)unsortedPoints;
- (NSArray *)sortChunksByDistFromCamera:(NSMutableArray *)unsortedChunks;
- (void)getNeighborsForChunkAtPoint:(GSVector3)p outNeighbors:(GSChunkVoxelData **)neighbors;

- (GSChunkGeometryData *)getChunkGeometryAtPoint:(GSVector3)p;
- (GSChunkVoxelData *)getChunkVoxelsAtPoint:(GSVector3)p;

@end


@implementation GSChunkStore

@synthesize activeRegionExtent;

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if(![defaults objectForKey:@"ActiveRegionExtent"]) {
        NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:@"256", @"ActiveRegionExtent", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}


+ (NSLock *)lockWhileLockingMultipleChunksVoxelData
{
    static dispatch_once_t onceToken;
    static NSLock *doingNeighborhoodLock = nil;
    
    dispatch_once(&onceToken, ^{
        doingNeighborhoodLock = [[NSLock alloc] init];
        [doingNeighborhoodLock setName:@"lockWhileLockingMultipleChunksVoxelData"];
    });
    
    return doingNeighborhoodLock;
}


+ (NSLock *)lockWhileLockingMultipleChunksSunlight
{
    static dispatch_once_t onceToken;
    static NSLock *doingNeighborhoodLock = nil;
    
    dispatch_once(&onceToken, ^{
        doingNeighborhoodLock = [[NSLock alloc] init];
        [doingNeighborhoodLock setName:@"lockWhileLockingMultipleChunksSunlight"];
    });
    
    return doingNeighborhoodLock;
}


- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
        terrainHeight = 40.0;
        folder = [GSChunkStore createWorldSaveFolderWithSeed:seed];
        groupForSaving = dispatch_group_create();
        
        camera = _camera;
        [camera retain];
        oldCenterChunkID = [self getChunkIDWithMinP:[self computeChunkMinPForPoint:[camera cameraEye]]];
        [oldCenterChunkID retain];
        
        terrainShader = _terrainShader;
        [terrainShader retain];
        
        numVBOGenerationsAllowedPerFrame = 1;
        numVBOGenerationsRemaining = numVBOGenerationsAllowedPerFrame;
        
        // Active region is bounded at y>=0.
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
        activeRegionExtent = GSVector3_Make(w, CHUNK_SIZE_Y, w);
        assert(fmodf(activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(activeRegionExtent.z, CHUNK_SIZE_Z) == 0);
        
        maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X) *
                          (activeRegionExtent.y/CHUNK_SIZE_Y) *
                          (2*activeRegionExtent.z/CHUNK_SIZE_Z);
        
        activeChunks = calloc(maxActiveChunks, sizeof(GSChunkGeometryData *));
        
        cacheGeometryData = [[NSCache alloc] init];
        [cacheGeometryData setCountLimit:INT_MAX];
        
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
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(groupForSaving, DISPATCH_TIME_FOREVER); // wait for save operations to complete
    NSLog(@"All chunks have been saved.");
}


- (void)dealloc
{
    [self waitForSaveToFinish];
    dispatch_release(groupForSaving);
    
    [cacheVoxelData release];
    [cacheGeometryData release];
    [camera release];
    [folder release];
    [terrainShader release];
    [self deallocChunksWithArray:activeChunks len:maxActiveChunks];
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
        
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunkGeometryData *chunk = activeChunks[i];
        assert(chunk);
        
        if(chunk->visible && [chunk drawGeneratingVBOsIfNecessary:(numVBOGenerationsRemaining > 0)]) {
            numVBOGenerationsRemaining--;
        }
    }
    
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    
    [terrainShader unbind];
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
    numVBOGenerationsRemaining = numVBOGenerationsAllowedPerFrame; // reset
    [self recalculateActiveChunksWithCameraModifiedFlags:flags];
}


- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)newBlock
{
    /* XXX: There is a bug where geometry may fail to update after changing a block in the chunk.
     *      This occurs frequently when running in Debug mode and infrequently when running in Release mode.
     */
    
    voxel_t *block;
    GSVector3 chunkLocalP;
    GSChunkVoxelData *chunk;
    
    chunk = [self getChunkVoxelsAtPoint:pos];
    [chunk retain];
    [chunk->lockVoxelData lockForWriting];
    
    chunkLocalP = GSVector3_Sub(pos, chunk.minP);
    block = [chunk getPointerToVoxelAtPoint:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];
    assert(block);
    *block = newBlock;
    
    [chunk->lockVoxelData unlockForWriting];
    
    [chunk markAsDirtyAndSpinOffSavingTask]; // save the changes asynchronously
    [chunk release];
    
    // Now update geometry for this chunk and its neighbors.
    // Do it all synchronously too, so changes will appear "immediately."
    GSChunkVoxelData *chunks[CHUNK_NUM_NEIGHBORS] = {nil};
    [self getNeighborsForChunkAtPoint:pos outNeighbors:chunks];
    
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSChunkVoxelData *neighbors[CHUNK_NUM_NEIGHBORS] = {nil};
        [self getNeighborsForChunkAtPoint:chunks[i].centerP outNeighbors:neighbors];
        [chunks[i] updateLightingWithNeighbors:neighbors doItSynchronously:YES];
        [[self getChunkGeometryAtPoint:chunks[i].centerP] updateWithVoxelData:neighbors doItSynchronously:YES];
    }
}


- (voxel_t)getVoxelAtPoint:(GSVector3)pos
{
    GSChunkVoxelData *chunk = [self getChunkVoxelsAtPoint:pos];
    [chunk retain];
    [chunk->lockVoxelData lockForReading];

    GSVector3 chunkLocalP = GSVector3_Sub(pos, chunk.minP);
    
    voxel_t block = [chunk getVoxelAtPoint:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];

    [chunk->lockVoxelData unlockForReading];
    [chunk release];
    
    return block;
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
                return NO;
            }
            
            // world does not extend below y=activeRegionExtent.y
            if(pos.y >= activeRegionExtent.y) {
                return NO;
            }
            
            voxel_t block = [self getVoxelAtPoint:pos];
            
            if(!block.empty) {
                foundAnything = YES;
                break;
            }
            
            prevD = d;
        }
        
        if(!foundAnything) {
            return NO;
        }
    }
    
    if(outDistanceBefore) {
        *outDistanceBefore = prevD;
    }
    
    if(outDistanceAfter) {
        *outDistanceAfter = d;
    }
    
    return YES;
}

@end


@implementation GSChunkStore (Private)

- (GSChunkGeometryData *)getChunkGeometryAtPoint:(GSVector3)p
{
    GSChunkGeometryData *geometry = nil;
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    chunk_id_t chunkID = [self getChunkIDWithMinP:minP];
    
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    geometry = [cacheGeometryData objectForKey:chunkID];
    if(!geometry) {
        GSChunkVoxelData *chunks[CHUNK_NUM_NEIGHBORS] = {nil};
        [self getNeighborsForChunkAtPoint:p outNeighbors:chunks];
        
        // Now that neighboring chunks are actually available, spin off a task to asynchronously update lighting in the chunk.
        [chunks[CHUNK_NEIGHBOR_CENTER] updateLightingWithNeighbors:chunks doItSynchronously:NO];
        
        geometry = [[[GSChunkGeometryData alloc] initWithMinP:minP voxelData:chunks] autorelease];
        
        [cacheGeometryData setObject:geometry forKey:chunkID];
    }
    
    return geometry;
}


- (void)getNeighborsForChunkAtPoint:(GSVector3)p outNeighbors:(GSChunkVoxelData **)neighbors;
{
    neighbors[CHUNK_NEIGHBOR_POS_X_NEG_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(+CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_POS_X_ZER_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(+CHUNK_SIZE_X, 0, 0))];
    neighbors[CHUNK_NEIGHBOR_POS_X_POS_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(+CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_NEG_X_NEG_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_NEG_X_ZER_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(-CHUNK_SIZE_X, 0, 0))];
    neighbors[CHUNK_NEIGHBOR_NEG_X_POS_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(-CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_ZER_X_NEG_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(0, 0, -CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_ZER_X_POS_Z] = [self getChunkVoxelsAtPoint:GSVector3_Add(p, GSVector3_Make(0, 0, +CHUNK_SIZE_Z))];
    neighbors[CHUNK_NEIGHBOR_CENTER] = [self getChunkVoxelsAtPoint:p];
}


- (GSChunkVoxelData *)getChunkVoxelsAtPoint:(GSVector3)p
{
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    chunk_id_t chunkID = [self getChunkIDWithMinP:minP];
    
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkVoxelData *voxels = [cacheVoxelData objectForKey:chunkID];
    if(!voxels) {
        voxels = [[[GSChunkVoxelData alloc] initWithSeed:seed
                                                    minP:minP
                                           terrainHeight:terrainHeight
                                                  folder:folder
                                          groupForSaving:groupForSaving] autorelease];
        
        [cacheVoxelData setObject:voxels forKey:chunkID];
    }
    
    return voxels;
}


- (void)deallocChunksWithArray:(GSChunkData **)array len:(size_t)len
{
    for(size_t i = 0; i < len; ++i)
    {
        [array[i] release];
        array[i] = nil;
    }
    free(array);
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
        GSVector3 centerA = [(GSBoxedVector *)a getVector];
        GSVector3 centerB = [(GSBoxedVector *)b getVector];
        float distA = GSVector3_Length(GSVector3_Sub(centerA, center));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, center));
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
}


+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed
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
    
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunkGeometryData *geometry = activeChunks[i];
        assert(geometry);
        geometry->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:geometry->corners]);
    }
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock
{
    const GSVector3 center = [camera cameraEye];
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
    NSMutableArray *tmpActiveChunks = [[NSMutableArray alloc] initWithCapacity:maxActiveChunks];
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunkGeometryData *geometry = activeChunks[i];
        
        if(geometry) {
            geometry->visible = NO;
            [tmpActiveChunks addObject:geometry];
        }
    }
    
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        [activeChunks[i] release];
        activeChunks[i] = nil;
    }
    
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
        size_t i = 0;
        for(GSBoxedVector *b in sortedChunks)
        {
            activeChunks[i] = [self getChunkGeometryAtPoint:[b getVector]];
            [activeChunks[i] retain];
            i++;
        }
        assert(i == maxActiveChunks);
        
        [unsortedChunks release];
    } else {
        __block size_t i = 0;
        [self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
            activeChunks[i] = [self getChunkGeometryAtPoint:p];
            [activeChunks[i] retain];
            i++;
        }];
        assert(i == maxActiveChunks);
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

@end
