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
#import "GSLightingBuffer.h"


typedef void (^terrain_generator_t)(GSVector3, voxel_t*);


@interface GSChunkVoxelData : GSChunkData
{
    NSURL *folder;
    dispatch_group_t groupForSaving;
    dispatch_queue_t chunkTaskQueue;
    
    GSReaderWriterLock *lockVoxelData;
    voxel_t *voxelData; // the voxels that make up the chunk
    
    GSLightingBuffer *directSunlight; // direct lighting from the sun
    GSLightingBuffer *indirectSunlight; // indirect lighting from the sun
    
    BOOL indirectSunlightIsOutOfDate; // indicates that indirect sunlight is out of date for this chunk.
    int indirectSunlightRebuildIsInFlight;
}

@property (readonly, nonatomic) voxel_t *voxelData;
@property (readonly, nonatomic) GSLightingBuffer *directSunlight;
@property (readonly, nonatomic) GSLightingBuffer *indirectSunlight;
@property (readonly, nonatomic) GSReaderWriterLock *lockVoxelData;
@property (assign, atomic) BOOL indirectSunlightIsOutOfDate;

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP;

- (id)initWithMinP:(GSVector3)minP
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         generator:(terrain_generator_t)callback;

// Must call after modifying voxel data and while still holding the lock on "lockVoxelData".
- (void)voxelDataWasModified;

/* Obtains a reader lock on the voxel data and allows the caller to access it in the specified block. */
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the voxel data and allows the caller to access it in the specified block. */
- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

// Rebuilds indirect sunlight for this chunk and then call the completion handler.
- (void)rebuildIndirectSunlightWithNeighborhood:(GSNeighborhood *)neighborhood completionHandler:(void (^)(void))completionHandler;

@end