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
}

@property (readonly, nonatomic) voxel_t *voxelData;
@property (readonly, nonatomic) GSLightingBuffer *directSunlight;
@property (readonly, nonatomic) GSLightingBuffer *indirectSunlight;
@property (readonly, nonatomic) GSReaderWriterLock *lockVoxelData;

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

/* Given a point in world-space, return a pointer to the indirect sunlight value at that point.
 * Assumes the caller is already holding the lock on indirectSunlight for reading.
 * If the point is not within the bounds of this chunk then this method returns NULL.
 */
- (uint8_t *)pointerToIndirectSunlightAtPoint:(GSVector3)worldSpacePos;

/* Given a point in world-space, return a pointer to the voxel at that point.
 * Assumes the caller is already holding "lockVoxelData" for reading.
 * If the point is not within the bounds of this chunk then this method returns NULL.
 */
- (uint8_t *)pointerToVoxelAtPointInWorldSpace:(GSVector3)worldSpacePos;

/* Writes indirect sunlight values for the specified sunlight propagation point (in world-space). May modify neigboring chunks too.
 * If indirect sunlight is removed then this can generate incorrect values as it can only ever brighten an area.
 * Assumes the caller has already holding the lock on indirectSunlight for writing for all chunks in the neighborhood.
 */
- (void)floodFillIndirectSunlightAtPoint:(GSVector3)worldSpacePos
                               neighbors:(GSNeighborhood *)neighbors
                               intensity:(int)intensity;

/* Assumes the caller is already holding "lockVoxelData" on all chunks in the neighborhood.
 * Returns YES if the point is a point where indirect sunlight should propagate with a flood-fill.
 */
- (BOOL)isSunlightPropagationPointAtPoint:(GSIntegerVector3)p neighborhood:(GSNeighborhood *)neighborhood;

@end