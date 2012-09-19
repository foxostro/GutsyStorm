//
//  GSGridNeighbors.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"
#import "GSIntegerVector3.h"


@class GSChunkVoxelData;


typedef enum
{
    CHUNK_NEIGHBOR_POS_X_NEG_Z = 0,
    CHUNK_NEIGHBOR_POS_X_ZER_Z = 1,
    CHUNK_NEIGHBOR_POS_X_POS_Z = 2,
    CHUNK_NEIGHBOR_NEG_X_NEG_Z = 3,
    CHUNK_NEIGHBOR_NEG_X_ZER_Z = 4,
    CHUNK_NEIGHBOR_NEG_X_POS_Z = 5,
    CHUNK_NEIGHBOR_ZER_X_NEG_Z = 6,
    CHUNK_NEIGHBOR_ZER_X_POS_Z = 7,
    CHUNK_NEIGHBOR_CENTER = 8,
    CHUNK_NUM_NEIGHBORS = 9
} neighbor_index_t;


@interface GSNeighborhood : NSObject
{
    GSChunkVoxelData *neighbors[CHUNK_NUM_NEIGHBORS];
}

+ (NSLock *)_sharedVoxelDataLock;
+ (NSLock *)_sharedSkylightLock;
+ (GSVector3)getOffsetForNeighborIndex:(neighbor_index_t)idx;

- (GSChunkVoxelData *)getNeighborAtIndex:(neighbor_index_t)idx;
- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(GSChunkVoxelData *)neighbor;
- (void)forEachNeighbor:(void (^)(GSChunkVoxelData*))block;

/* Given a position relative to this voxel, and a list of neighboring chunks, return the chunk that contains the specified position.
 * also returns the position in the local coordinate system of that chunk.
 * The position must be contained in this chunk or any of the specified neighbors.
 */
- (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3 *)chunkLocalP;

/* Returns YES if the specified block in the neighborhood is empty. Positions are specified in chunk-local space relative to the
 * center chunk of the neighborhood. Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 * Assumes the caller is already holding "lockVoxelData" on all chunks in the neighborhood.
 */
- (BOOL)isEmptyAtPoint:(GSIntegerVector3)p;

/* Returns the lighting value at the specified block position for the specified lighting buffer.
 * Assumes the caller is already holding the lock on this buffer on all neighbors.
 */
- (uint8_t)lightAtPoint:(GSIntegerVector3)p buffer:(SEL)buffer;

/* Executes the specified block while holding the voxel data locks (for reading) on all chunks in the neighborhood. */
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Executes the specified block while holding the voxel data locks (for writing) on all chunks in the neighborhood. */
- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Executes the specified block while holding the locks (for reading) on the specified lighting buffer,
 * for all chunks in the neighborhood.
 */
- (void)readerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block;

/* Executes the specified block while holding the sunlight data locks (for writing) on the specified lighting vbuffer,
 * for all chunks in the neighborhood.
 */
- (void)writerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block;

@end
