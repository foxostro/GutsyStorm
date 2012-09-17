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
    voxel_t *voxelData;
    
    GSReaderWriterLock *lockSunlight;
    uint8_t *sunlight;
}

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP;

- (id)initWithMinP:(GSVector3)minP
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         generator:(terrain_generator_t)callback;

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



/* Obtains a reader lock on the voxel data and allows the caller to access it in the specified block. */
- (void)readerAccessToSunlightDataUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the voxel data and allows the caller to access it in the specified block. */
- (void)writerAccessToSunlightDataUsingBlock:(void (^)(void))block;

/* Returns the lock used to protext the sunlight data buffer.
 * You probably don't want this.
 * Use the block-based methods instead.
 */
- (GSReaderWriterLock *)getSunlightDataLock;



// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

// Assumes the caller is already holding "lockSunlight".
- (uint8_t)getSunlightAtPoint:(GSIntegerVector3)chunkLocalP;

// Assumes the caller is already holding "lockSunlight" on all neighbors and "lockVoxelData" on self, at least.
- (void)calculateSunlightAtPoint:(GSIntegerVector3)p
                       neighbors:(GSNeighborhood *)neighbors
                     outLighting:(block_lighting_t *)lighting;

@end