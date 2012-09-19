//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSChunkData.h"
#import "GSIntegerVector3.h"
#import "GSReaderWriterLock.h"
#import "Voxel.h"
#import "GSNeighborhood.h"


typedef void (^terrain_generator_t)(GSVector3, voxel_t*);


@interface GSChunkVoxelData : GSChunkData
{
    NSURL *folder;
    BOOL dirty;
    dispatch_group_t groupForSaving;
    dispatch_queue_t chunkTaskQueue;
    
    GSReaderWriterLock *lockVoxelData;
    voxel_t *voxelData; // the voxels that make up the chunk
    
    GSReaderWriterLock *lockSkylight;
    uint8_t *skylight; // direct lighting from the sky
}

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP;

- (id)initWithMinP:(GSVector3)minP
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         generator:(terrain_generator_t)callback;

// Recalculates lighting values (indirect sunlight, direct skylight, torchlight) for the chunk.
- (void)updateLightingWithNeighbors:(GSNeighborhood *)neighbors doItSynchronously:(BOOL)sync;

- (void)markAsDirtyAndSpinOffSavingTask;



/* Obtains a reader lock on the voxel data and allows the caller to access it in the specified block. */
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the voxel data and allows the caller to access it in the specified block. */
- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Returns the lock used to protext the voxel data buffer.
 * You probably don't want this.
 * Use the block-based methods instead, or use methods in GSNeighborhood when dealing with multiple chunks.
 */
- (GSReaderWriterLock *)getVoxelDataLock;



/* Obtains a reader lock on the skylight data and allows the caller to access it in the specified block. */
- (void)readerAccessToSkylightDataUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the skylight data and allows the caller to access it in the specified block. */
- (void)writerAccessToSkylightDataUsingBlock:(void (^)(void))block;

/* Returns the lock used to protext the skylight data buffer.
 * You probably don't want this.
 * Use the block-based methods instead.
 */
- (GSReaderWriterLock *)getSkylightDataLock;



// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

/* Returns the skylight value for the specified point that was calculated earlier.
 * Assumes the caller is already holding "lockSkylight".
 */
- (uint8_t)getSkylightAtPoint:(GSIntegerVector3)chunkLocalP;

/* Returns a pointer to the skylight value for the specified point that was calculated earlier.
 * Assumes the caller is already holding "lockSkylight".
 */
- (uint8_t *)getPointerToSkylightAtPoint:(GSIntegerVector3)chunkLocalP;

/* Gets a smooth skylight lighting value by interpolating block skylight values around the specified point.
 * Assumes the caller is already holding "lockSkylight" on all neighbors and "lockVoxelData" on self, at least.
 */
- (void)interpolateSkylightAtPoint:(GSIntegerVector3)p
                         neighbors:(GSNeighborhood *)neighbors
                       outLighting:(block_lighting_t *)lighting;

@end