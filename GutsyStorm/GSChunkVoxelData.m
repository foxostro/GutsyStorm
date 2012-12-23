//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSBoxedVector.h"


static const GSIntegerVector3 offsets[FACE_NUM_FACES] = {
    { 1, 0, 0},
    {-1, 0, 0},
    { 0, 1, 0},
    { 0,-1, 0},
    { 0, 0, 1},
    { 0, 0,-1},
};

static const GSIntegerVector3 combinedMinP = {-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z};
static const GSIntegerVector3 combinedMaxP = {2*CHUNK_SIZE_X, CHUNK_SIZE_Y, 2*CHUNK_SIZE_Z};


@interface GSChunkVoxelData (Private)

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (NSError *)loadVoxelDataFromFile:(NSURL *)url;
- (void)recalcOutsideVoxelsNoLock;
- (void)generateVoxelDataWithCallback:(terrain_generator_t)callback;
- (void)saveVoxelDataToFile;
- (void)saveSunlightDataToFile;
- (void)loadOrGenerateVoxelData:(terrain_generator_t)callback completionHandler:(void (^)(void))completionHandler;
- (void)tryToLoadSunlightData;

@end


@implementation GSChunkVoxelData

@synthesize voxelData;
@synthesize sunlight;
@synthesize lockVoxelData;
@synthesize dirtySunlight;

+ (NSString *)fileNameForVoxelDataFromMinP:(GLKVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}


+ (NSString *)fileNameForSunlightDataFromMinP:(GLKVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.sunlight.dat", minP.x, minP.y, minP.z];
}


- (id)initWithMinP:(GLKVector3)_minP
            folder:(NSURL *)_folder
    groupForSaving:(dispatch_group_t)_groupForSaving
    chunkTaskQueue:(dispatch_queue_t)_chunkTaskQueue
         generator:(terrain_generator_t)callback
{
    self = [super initWithMinP:_minP];
    if (self) {
        assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));
        
        groupForSaving = _groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        dispatch_retain(groupForSaving);
        
        chunkTaskQueue = _chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);
        
        folder = _folder;
        [folder retain];
        
        lockVoxelData = [[GSReaderWriterLock alloc] init];
        [lockVoxelData lockForWriting]; // This is locked initially and unlocked at the end of the first update.
        voxelData = NULL;
        
        sunlight = [[GSLightingBuffer alloc] initWithDimensions:GSIntegerVector3_Make(3*CHUNK_SIZE_X,CHUNK_SIZE_Y,3*CHUNK_SIZE_Z)];
        dirtySunlight = YES;
        
        // The initial loading from disk preceeds all attempts to generate new sunlight data.
        OSAtomicCompareAndSwapIntBarrier(0, 1, &updateForSunlightInFlight);
        
        // Fire off asynchronous task to load or generate voxel data.
        dispatch_async(chunkTaskQueue, ^{
            [self allocateVoxelData];
            
            [self tryToLoadSunlightData];
            OSAtomicCompareAndSwapIntBarrier(1, 0, &updateForSunlightInFlight); // reset
            
            [self loadOrGenerateVoxelData:callback completionHandler:^{
                [self recalcOutsideVoxelsNoLock];
                [lockVoxelData unlockForWriting];
                // We don't need to call -voxelDataWasModified in the special case of initialization.
            }];
        });
    }
    
    return self;
}


- (void)dealloc
{
    dispatch_release(groupForSaving);
    dispatch_release(chunkTaskQueue);
    [folder release];
    
    [self destroyVoxelData];
    [lockVoxelData release];
    
    [sunlight release];
    
    [super dealloc];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)voxelAtLocalPosition:(GSIntegerVector3)p
{
    return *[self pointerToVoxelAtLocalPosition:p];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t *)pointerToVoxelAtLocalPosition:(GSIntegerVector3)p
{
    assert(voxelData);
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    
    size_t idx = INDEX_BOX(p, ivecZero, chunkSize);
    assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return &voxelData[idx];
}


- (void)voxelDataWasModified
{
    [self recalcOutsideVoxelsNoLock];
    
    // Caller must make sure to update sunlight later...
    dirtySunlight = YES;
    
    // Spin off a task to save the chunk.
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
    block();
    [self voxelDataWasModified];
    [lockVoxelData unlockForWriting];
}


/* Copy the voxel data for the neighborhood into a new buffer and return the buffer. If the method would block when taking the
 * locks on the neighborhood then instead return NULL. The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y
 * elements in size and may be indexed using the INDEX2 macro.
 * Assumes the caller has already locked the voxelData for chunks in the neighborhood (for reading).
 */
- (voxel_t *)newVoxelBufferWithNeighborhood:(GSNeighborhood *)neighborhood
{
    static const size_t size = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    voxel_t *combinedVoxelData = combinedVoxelData = malloc(size*sizeof(voxel_t));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
    }
    
    static ssize_t offsetsX[CHUNK_NUM_NEIGHBORS];
    static ssize_t offsetsZ[CHUNK_NUM_NEIGHBORS];
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        for(neighbor_index_t i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            GLKVector3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            offsetsX[i] = offset.x;
            offsetsZ[i] = offset.z;
        }
    });
    
    [neighborhood enumerateNeighborsWithBlock2:^(neighbor_index_t i, GSChunkVoxelData *voxels) {
        const voxel_t *data = voxels.voxelData;
        ssize_t offsetX = offsetsX[i];
        ssize_t offsetZ = offsetsZ[i];
        
        GSIntegerVector3 p;
        FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
        {
            assert(p.x >= 0 && p.x < chunkSize.x);
            assert(p.y >= 0 && p.y < chunkSize.y);
            assert(p.z >= 0 && p.z < chunkSize.z);
            
            size_t dstIdx = INDEX_BOX(GSIntegerVector3_Make(p.x+offsetX, p.y, p.z+offsetZ), combinedMinP, combinedMaxP);
            size_t srcIdx = INDEX_BOX(p, ivecZero, chunkSize);
            
            assert(dstIdx < size);
            assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));
            assert(sizeof(combinedVoxelData[0]) == sizeof(data[0]));

            memcpy(&combinedVoxelData[dstIdx], &data[srcIdx], CHUNK_SIZE_Y*sizeof(combinedVoxelData[0]));
        }
    }];
    
    return combinedVoxelData;
}


- (BOOL)isAdjacentToSunlightAtPoint:(GSIntegerVector3)p
                         lightLevel:(int)lightLevel
                  combinedVoxelData:(voxel_t *)combinedVoxelData
       combinedSunlightData:(voxel_t *)combinedSunlightData
{
    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        GSIntegerVector3 a = GSIntegerVector3_Add(p, offsets[i]);
        
        if(a.x < -CHUNK_SIZE_X || a.x >= (2*CHUNK_SIZE_X) ||
           a.z < -CHUNK_SIZE_Z || a.z >= (2*CHUNK_SIZE_Z) ||
           a.y < 0 || a.y >= CHUNK_SIZE_Y) {
            continue; // The point is out of bounds, so bail out.
        }
        
        size_t idx = INDEX_BOX(a, combinedMinP, combinedMaxP);
        
        if(!isVoxelEmpty(combinedVoxelData[idx])) {
            continue;
        }
        
        if(combinedSunlightData[idx] == lightLevel) {
            return YES;
        }
    }
    
    return NO;
}


/* Generate and return  sunlight data for this chunk from the specified voxel data buffer. The voxel data buffer must be
 * (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and should contain voxel data for the entire local neighborhood.
 * The returned sunlight buffer is also this size and may also be indexed using the INDEX2 macro. Only the sunlight values for the
 * region of the buffer corresponding to this chunk should be considered to be totally correct.
 * Assumes the caller has already locked the sunlight buffer for reading (sunlight.lockLightingBuffer).
 */
- (void)fillSunlightBufferUsingCombinedVoxelData:(voxel_t *)combinedVoxelData
{
    GSIntegerVector3 p;
    
    uint8_t *combinedSunlightData = sunlight.lightingBuffer;
    
    FOR_BOX(p, combinedMinP, combinedMaxP)
    {
        size_t idx = INDEX_BOX(p, combinedMinP, combinedMaxP);
        voxel_t voxel = combinedVoxelData[idx];
        BOOL directlyLit = isVoxelEmpty(voxel) && isVoxelOutside(voxel);
        combinedSunlightData[idx] = directlyLit ? CHUNK_LIGHTING_MAX : 0;
    }

    // Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
    // Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
    // Set the blocks we find to the next lower light level.
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        FOR_BOX(p, combinedMinP, combinedMaxP)
        {
            size_t idx = INDEX_BOX(p, combinedMinP, combinedMaxP);
            voxel_t voxel = combinedVoxelData[idx];
            
            if(!isVoxelEmpty(voxel) || isVoxelOutside(voxel)) {
                continue;
            }
            
            if([self isAdjacentToSunlightAtPoint:p
                                      lightLevel:lightLevel
                               combinedVoxelData:combinedVoxelData
                    combinedSunlightData:combinedSunlightData]) {
                uint8_t *val = &combinedSunlightData[idx];
                *val = MAX(*val, lightLevel - 1);
            }
        }
    }
}


- (BOOL)tryToRebuildSunlightWithNeighborhood:(GSNeighborhood *)neighborhood completionHandler:(void (^)(void))completionHandler
{
    BOOL success = NO;
    __block voxel_t *buf = NULL;
    
    if(!OSAtomicCompareAndSwapIntBarrier(0, 1, &updateForSunlightInFlight)) {
        DebugLog(@"Can't update sunlight: already in-flight.");
        return NO; // an update is already in flight, so bail out now
    }
    
    if(![sunlight.lockLightingBuffer tryLockForWriting]) {
        DebugLog(@"Can't update sunlight: sunlight buffer is busy."); // This failure really shouldn't happen much...
        success = NO;
        goto cleanup1;
    }
    
    // Try to copy the entire neighborhood's voxel data into one large buffer.
    if(![neighborhood tryReaderAccessToVoxelDataUsingBlock:^{ buf = [self newVoxelBufferWithNeighborhood:neighborhood]; }]) {
        DebugLog(@"Can't update sunlight: voxel data buffers are busy.");
        success = NO;
        goto cleanup2;
    }
    
    // Actually generate sunlight data.
    [self fillSunlightBufferUsingCombinedVoxelData:buf];
    
    dirtySunlight = NO;
    success = YES;
    
    // Spin off a task to save sunlight data to disk.
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_async(groupForSaving, queue, ^{
        [self saveSunlightDataToFile];
    });
    
    completionHandler(); // Only call the completion handler if the update was successful.
    
cleanup2:
    [sunlight.lockLightingBuffer unlockForWriting];
cleanup1:
    OSAtomicCompareAndSwapIntBarrier(1, 0, &updateForSunlightInFlight); // reset
    free(buf);
    return success;
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


- (void)saveSunlightDataToFile
{
    NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForSunlightDataFromMinP:minP]
                        relativeToURL:folder];
    [sunlight saveToFile:url];
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
                voxel_t *voxel = [self pointerToVoxelAtLocalPosition:p];
                
                if(!isVoxelEmpty(*voxel)) {
                    break;
                }
            }
            
            for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
            {
                GSIntegerVector3 p = {x, y, z};
                voxel_t *voxel = [self pointerToVoxelAtLocalPosition:p];
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
    
    GSIntegerVector3 p;
    FOR_BOX(p, ivecZero, chunkSize)
    {
        generator(GLKVector3Add(GLKVector3Make(p.x, p.y, p.z), minP),
                  [self pointerToVoxelAtLocalPosition:p]);
        
        // whether the block is outside or not is calculated later
    }
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk voxel data. It took %.3fs", timeEnd - timeStart);
}


// Attempt to load chunk data from file asynchronously.
- (NSError *)loadVoxelDataFromFile:(NSURL *)url
{
    const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSFileNotFoundError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"Voxel data file is not present."}];
    }
    
    // Read the contents of the file into "voxelData".
    NSData *data = [[NSData alloc] initWithContentsOfURL:url];
    if([data length] != len) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"Voxel data file is of unexpected length."}];
    }
    [data getBytes:voxelData length:len];
    [data release];
    
    return nil;
}


- (void)loadOrGenerateVoxelData:(terrain_generator_t)callback completionHandler:(void (^)(void))completionHandler
{
    NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:minP] relativeToURL:folder];
    NSError *error = [self loadVoxelDataFromFile:url];
    
    if(error) {
        if((error.code == GSInvalidChunkDataOnDiskError) || (error.code == GSFileNotFoundError)) {
            [self generateVoxelDataWithCallback:callback];
            [self saveVoxelDataToFile];
        } else {
            [NSException raise:@"Runtime Error" format:@"Error %ld: %@", (long)error.code, error.localizedDescription];
        }
    }

    completionHandler();
}


- (void)tryToLoadSunlightData
{
    NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForSunlightDataFromMinP:minP]
                        relativeToURL:folder];
    
    [sunlight tryToLoadFromFile:url completionHandler:^{
        dirtySunlight = NO;
    }];
}

@end