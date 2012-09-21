//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSBoxedVector.h"


@interface GSChunkVoxelData (Private)

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (void)loadVoxelDataFromFile:(NSURL *)url;
- (void)recalcOutsideVoxelsNoLock;
- (void)generateVoxelDataWithCallback:(terrain_generator_t)callback;
- (void)saveVoxelDataToFile;
- (void)fillDirectSunlightBuffer;

@end


@implementation GSChunkVoxelData

@synthesize voxelData;
@synthesize directSunlight;
@synthesize indirectSunlight;
@synthesize lockVoxelData;

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}


- (id)initWithMinP:(GSVector3)_minP
            folder:(NSURL *)_folder
    groupForSaving:(dispatch_group_t)_groupForSaving
    chunkTaskQueue:(dispatch_queue_t)_chunkTaskQueue
         generator:(terrain_generator_t)callback
{
    self = [super initWithMinP:_minP];
    if (self) {
        groupForSaving = _groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        dispatch_retain(groupForSaving);
        
        chunkTaskQueue = _chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);
        
        folder = _folder;
        [folder retain];
        
        lockVoxelData = [[GSReaderWriterLock alloc] init];
        [lockVoxelData lockForWriting]; // This is locked initially and unlocked at the end of the first update.
        voxelData = NULL;
        
        directSunlight = [[GSLightingBuffer alloc] init];
        [directSunlight.lockLightingBuffer lockForWriting]; // locked initially and unlocked at the end of the first update
        
        indirectSunlight = [[GSLightingBuffer alloc] init];
        [indirectSunlight.lockLightingBuffer lockForWriting]; // locked initially and unlocked at the end of the first update
        hasHadFirstIndirectLightingUpdate = NO;
        
        // Fire off asynchronous task to generate voxel data.
        dispatch_async(chunkTaskQueue, ^{
            NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:minP]
                                relativeToURL:folder];
            
            [self allocateVoxelData];
            
            if([url checkResourceIsReachableAndReturnError:NULL]) {
                // Load chunk from disk.
                [self loadVoxelDataFromFile:url];
            } else {
                // Generate chunk from scratch.
                [self generateVoxelDataWithCallback:callback];
                [self saveVoxelDataToFile];
            }
            
            [self recalcOutsideVoxelsNoLock];
            [lockVoxelData unlockForWriting]; // We don't need to call -voxelDataWasModified in the special case of initialization.
            
            // Generate direct sunlight for this chunk, which does not depend on neighboring chunks.
            [self fillDirectSunlightBuffer];
            [directSunlight.lockLightingBuffer unlockForWriting];
            
        });
    }
    
    return self;
}


- (void)dealloc
{
    dispatch_release(groupForSaving);
    dispatch_release(chunkTaskQueue);
    [folder release];
    
    [lockVoxelData lockForWriting];
    [self destroyVoxelData];
    [lockVoxelData unlockForWriting];
    [lockVoxelData release];
    
    [directSunlight release];
    [indirectSunlight release];
    
    [super dealloc];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)p
{
    return *[self getPointerToVoxelAtPoint:p];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)p
{
    assert(voxelData);
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    
    size_t idx = INDEX(p.x, p.y, p.z);
    assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return &voxelData[idx];
}


- (void)voxelDataWasModified
{
    [self recalcOutsideVoxelsNoLock];
    
    // Rebuild direct sunlight data.
    [directSunlight.lockLightingBuffer lockForWriting];
    [self fillDirectSunlightBuffer];
    [directSunlight.lockLightingBuffer unlockForWriting];
    
    /* Spin off a task to save the chunk.
     * This is latency sensitive, so submit to the global queue. Do not use `chunkTaskQueue' as that would cause the block to be
     * added to the end of a long queue of basically serialized background tasks.
     */
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_async(groupForSaving, queue, ^{
        [lockVoxelData lockForReading];
        [self saveVoxelDataToFile];
        [lockVoxelData unlockForReading];
    });
}


- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    [lockVoxelData lockForReading];
    block();
    [lockVoxelData unlockForReading];
}


- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    [lockVoxelData lockForWriting];
    block(); // rely on caller to call -voxelDataWasModified
    [lockVoxelData unlockForWriting];
}


/* Writes indirect sunlight values for the specified sunlight propagation point (in world-space). May modify neigboring chunks too.
 * If indirect sunlight is removed then this can generate incorrect values as it can only ever brighten an area.
 * Assumes the caller has already holding the lock on indirectSunlight for writing for all chunks in the neighborhood.
 */
- (void)floodFillIndirectSunlightAtPoint:(GSIntegerVector3)p
                       combinedVoxelData:(voxel_t *)combinedVoxelData
                       combinedIndirectSunlightData:(voxel_t *)combinedIndirectSunlightData
                               intensity:(int)intensity
{
    if(intensity <= 0) {
        return; // Well, we're done, so bail out.
    }
    
    if(p.x < -CHUNK_SIZE_X || p.x >= (2*CHUNK_SIZE_X) ||
       p.z < -CHUNK_SIZE_Z || p.z >= (2*CHUNK_SIZE_Z) ||
       p.y < 0 || p.y >= CHUNK_SIZE_Y) {
        return; // The point is out of bounds, so bail out.
    }
    
    if(!isVoxelEmpty(combinedVoxelData[INDEX2(p.x, p.y, p.z)])) {
        return; // Indirect sunlight cannot propagate from this point, so bail out.
    }
    
    uint8_t *value = &combinedIndirectSunlightData[INDEX2(p.x, p.y, p.z)];
    
    *value = MAX(intensity, *value); // this flood-fill can only ever brighten a voxel
    
    static const GSIntegerVector3 offsets[FACE_NUM_FACES] = {
        { 1, 0, 0},
        {-1, 0, 0},
        { 0, 1, 0},
        { 0,-1, 0},
        { 0, 0, 1},
        { 0, 0,-1},
    };
    
    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        [self floodFillIndirectSunlightAtPoint:GSIntegerVector3_Add(p, offsets[i])
                             combinedVoxelData:combinedVoxelData
                  combinedIndirectSunlightData:combinedIndirectSunlightData
                                     intensity:intensity-1];
    }
}


- (void)rebuildIndirectSunlightWithNeighborhood:(GSNeighborhood *)neighborhood
{
    GSIntegerVector3 p;
    const size_t size = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    
    assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));
    
    CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    voxel_t *combinedVoxelData = malloc(size*sizeof(voxel_t));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
    }
    
    // Allocate a buffer large enough to hold the entire neighborhood's indirect sunlight values.
    uint8_t *combinedIndirectSunlightData = calloc(size, sizeof(uint8_t));
    if(!combinedIndirectSunlightData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedIndirectSunlightData."];
    }
    
    // Copy the entire neighborhood's voxel data into the large buffer.
    [neighborhood readerAccessToVoxelDataUsingBlock:^{
        GSIntegerVector3 p;
        for(p.x = -CHUNK_SIZE_X; p.x < 2*CHUNK_SIZE_X; ++p.x)
        {
            for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
            {
                for(p.z = -CHUNK_SIZE_Z; p.z < 2*CHUNK_SIZE_Z; ++p.z)
                {
                    GSIntegerVector3 ap = p;
                    GSChunkVoxelData *chunk = [neighborhood getNeighborVoxelAtPoint:&ap];
                    combinedVoxelData[INDEX2(p.x, p.y, p.z)] = chunk.voxelData[INDEX(ap.x, ap.y, ap.z)];
                }
            }
        }
    }];
    
    // Identify points out of which indirect sunlight should propagate and do a flood-fill from each one.
    for(p.x = -CHUNK_LIGHTING_MAX; p.x < (CHUNK_SIZE_X+CHUNK_LIGHTING_MAX); ++p.x)
    {
        for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
        {
            for(p.z = -CHUNK_LIGHTING_MAX; p.z < (CHUNK_SIZE_Z+CHUNK_LIGHTING_MAX); ++p.z)
            {
                voxel_t voxel = combinedVoxelData[INDEX2(p.x, p.y, p.z)];
                
                if(!isVoxelEmpty(voxel)) {
                    continue; // skip, as non-empty blocks can never propagate indirect sunlight
                }
                
                if(isVoxelOutside(voxel)) {
                    continue; // skip, as outside blocks can never be the starting points for indirect sunlight propagation
                }
                
                // Check neighboring voxels in the six cardinal directions
                static const GSIntegerVector3 offsets[FACE_NUM_FACES] = {
                    { 1, 0, 0},
                    {-1, 0, 0},
                    { 0, 1, 0},
                    { 0,-1, 0},
                    { 0, 0, 1},
                    { 0, 0,-1},
                };
                
                for(face_t i=0; i<FACE_NUM_FACES; ++i)
                {
                    GSIntegerVector3 q = GSIntegerVector3_Add(p, offsets[i]);
                    
                    if(q.x >= -CHUNK_SIZE_X && q.x < (2*CHUNK_SIZE_X) &&
                       q.z >= -CHUNK_SIZE_Z && q.z < (2*CHUNK_SIZE_Z) &&
                       q.y >= 0 && q.y < CHUNK_SIZE_Y) {
                        voxel_t neighborVoxel = combinedVoxelData[INDEX2(q.x, q.y, q.z)];
                        
                        if(isVoxelEmpty(neighborVoxel) && isVoxelOutside(neighborVoxel)) {
                            // This voxel receives sunlight from a neighboring voxel and we need to flood-fill.
                            [self floodFillIndirectSunlightAtPoint:p
                                                 combinedVoxelData:combinedVoxelData
                                      combinedIndirectSunlightData:combinedIndirectSunlightData
                                                         intensity:CHUNK_LIGHTING_MAX-1];
                            
                            break; // No point in continuing the loop. Bail out.
                        }
                    }
                }
            }
        }
    }
    
    /* The lock is taken in the constructor so that no clients can read this at all until after the first update. If this is not
     * the first update then it is necessary to grab the lock here.
     */
    if(YES == hasHadFirstIndirectLightingUpdate) {
        [indirectSunlight.lockLightingBuffer lockForWriting];
    }
    
    // Copy the central portion of the large lighting buffer to indirectSunlight.
    for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
    {
        for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
        {
            for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
            {
                indirectSunlight.lightingBuffer[INDEX(p.x, p.y, p.z)] = combinedIndirectSunlightData[INDEX2(p.x, p.y, p.z)];
            }
        }
    }
    
    hasHadFirstIndirectLightingUpdate = YES;
    CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"Finished rebuilding indirect sunlight. It took %.3fs", timeEnd - timeStart);
    [indirectSunlight.lockLightingBuffer unlockForWriting];
    
    free(combinedVoxelData);
    free(combinedIndirectSunlightData);
}

@end


@implementation GSChunkVoxelData (Private)

// Assumes the caller is already holding "lockVoxelData" for reading.
- (void)saveVoxelDataToFile
{
    const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
    
    NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:minP]
                        relativeToURL:folder];
    
    [[NSData dataWithBytes:voxelData length:len] writeToURL:url atomically:YES];
}


// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
    [self destroyVoxelData];
    
    voxelData = malloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t));
    if(!voxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for chunk's voxelData"];
    }
}


// Assumes the caller is already holding "lockVoxelData".
- (void)destroyVoxelData
{
    free(voxelData);
    voxelData = NULL;
}


// Assumes the caller is already holding "lockVoxelData".
- (void)recalcOutsideVoxelsNoLock
{
    // Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
    // We assume here that the chunk is the height of the world.
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
        {
            // Get the y value of the highest non-empty voxel in the chunk.
            ssize_t heightOfHighestVoxel;
            for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
            {
                GSIntegerVector3 p = {x, heightOfHighestVoxel, z};
                voxel_t *voxel = [self getPointerToVoxelAtPoint:p];
                
                if(!isVoxelEmpty(*voxel)) {
                    break;
                }
            }
            
            for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
            {
                GSIntegerVector3 p = {x, y, z};
                voxel_t *voxel = [self getPointerToVoxelAtPoint:p];
                BOOL outside = y >= heightOfHighestVoxel;
                
                markVoxelAsOutside(outside, voxel);
            }
        }
    }
}


/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 *
 * Assumes the caller already holds "lockVoxelData" for writing.
 */
- (void)generateVoxelDataWithCallback:(terrain_generator_t)generator
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
                generator(GSVector3_Add(GSVector3_Make(x, y, z), minP),
                          [self getPointerToVoxelAtPoint:GSIntegerVector3_Make(x, y, z)]);
                
                // whether the block is outside or not is calculated later
            }
       }
    }
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk voxel data. It took %.3fs", timeEnd - timeStart);
}


/* Returns YES if the chunk data is reachable on the filesystem and loading was successful.
 * Assumes the caller already holds "lockVoxelData" for writing.
 */
- (void)loadVoxelDataFromFile:(NSURL *)url
{
    const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
    
    // Read the contents of the file into "voxelData".
    NSData *data = [[NSData alloc] initWithContentsOfURL:url];
    if([data length] != len) {
        [NSException raise:@"Runtime Error"
                    format:@"Unexpected length of data for chunk. Got %zu bytes. Expected %zu bytes.", (size_t)[data length], len];
    }
    [data getBytes:voxelData length:len];
    [data release];
}


// Assumes the caller has already holding the lock on "directSunlight" for writing and "lockVoxelData" for reading.
- (void)fillDirectSunlightBuffer
{
    GSIntegerVector3 p;
    for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
    {
        for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
        {
            for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
            {
                size_t idx = INDEX(p.x, p.y, p.z);
                assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
                
                // This is "hard" lighting with exactly two lighting levels.
                // Solid blocks always have zero sunlight. They pick up light from surrounding air.
                if(isVoxelEmpty(voxelData[idx]) && isVoxelOutside(voxelData[idx])) {
                    directSunlight.lightingBuffer[idx] = CHUNK_LIGHTING_MAX;
                } else {
                    directSunlight.lightingBuffer[idx] = 0;
                }
            }
        }
    }
}

@end