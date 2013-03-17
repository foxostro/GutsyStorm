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
#import "GSMutableByteBuffer.h"


typedef void (^terrain_generator_t)(GLKVector3, voxel_t*);
typedef void (^terrain_post_processor_t)(size_t count, voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP);


@interface GSChunkVoxelData : GSChunkData

@property (readonly, nonatomic) voxel_t *voxelData;
@property (readonly, nonatomic) GSMutableByteBuffer *sunlight;
@property (assign) BOOL dirtySunlight;

/* There are circumstances when it is necessary to use this lock directly, but in most cases the reader/writer accessor methods
 * here and in GSNeighborhood should be preferred.
 */
@property (readonly, nonatomic) GSReaderWriterLock *lockVoxelData;

+ (NSString *)fileNameForVoxelDataFromMinP:(GLKVector3)minP;
+ (NSString *)fileNameForSunlightDataFromMinP:(GLKVector3)minP;

- (id)initWithMinP:(GLKVector3)minP
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    queueForSaving:(dispatch_queue_t)queueForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         generator:(terrain_generator_t)generator
     postProcessor:(terrain_post_processor_t)postProcessor;

// Must call after modifying voxel data and while still holding the lock on "lockVoxelData".
- (void)voxelDataWasModified;

// Obtains a reader lock on the voxel data and allows the caller to access it in the specified block.
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Tries to obtain a reader lock on the voxel data and allows the caller to access it in the specified block.
 * If the lock cannot be taken without blocking then this returns NO immediately. Otherwise, returns YES after executing the block.
 */
- (BOOL)tryReaderAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the voxel data and allows the caller to access it in the specified block. Calls -voxelDataWasModified
 * after the block returns.
 */
- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)voxelAtLocalPosition:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)pointerToVoxelAtLocalPosition:(GSIntegerVector3)chunkLocalP;

/* Try to immediately update sunlight using voxel data for the local neighborhood. If it is not possible to immediately take all
 * the locks on necessary resources then this method aborts the update and returns NO. If it is able to complete the update
 * successfully then it returns YES and marks this GSChunkVoxelData as being clean. (dirtySunlight=NO)
 * If the update was able to complete succesfully then the completionHandler block is called.
 */
- (BOOL)tryToRebuildSunlightWithNeighborhood:(GSNeighborhood *)neighborhood completionHandler:(void (^)(void))completionHandler;

@end