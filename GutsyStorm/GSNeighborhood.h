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

+ (NSLock *)globalLock;
+ (GSVector3)getOffsetForNeighborIndex:(neighbor_index_t)idx;

- (GSChunkVoxelData *)getNeighborAtIndex:(neighbor_index_t)idx;
- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(GSChunkVoxelData *)neighbor;
- (void)forEachNeighbor:(void (^)(GSChunkVoxelData*))block;

/* Given a position relative to this voxel, return the chunk that contains the specified position.
 * Also returns the position in the local coordinate system of that chunk.
 * The position must be within the neighborhood.
 */
- (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3 *)chunkLocalP;

/* Given a position in world-space, return a pointer to the indirect sunlight value for that point.
 * The position must be within the neighborhood, else this method returns NULL.
 * Assumes the caller is holding the lock on indirectSunlight for reading on all chunks in the neighborhood.
 */
- (uint8_t *)pointerToIndirectSunlightAtPoint:(GSVector3)worldSpacePos;

/* Returns YES if the specified block in the neighborhood is empty. Positions are specified in chunk-local space relative to the
 * center chunk of the neighborhood. Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 * Assumes the caller is already holding "lockVoxelData" on all chunks in the neighborhood.
 */
- (BOOL)isEmptyAtPoint:(GSIntegerVector3)p;

/* Returns YES if the specified block in the neighborhood can propagate indirect sunlight. The point is specified in world-space
 * coordinates and must be contained by the neighborhood.
 * Assumes the caller is already holding "lockVoxelData" on all chunks in the neighborhood.
 */
- (BOOL)canPropagateIndirectSunlightFromPoint:(GSVector3)worldSpacePos;

// Searches the neighborhood for sunlight propagation points and calls the handler block for each one.
- (void)findSunlightPropagationPointsWithHandler:(void (^)(GSVector3 p))handler;

/* Returns the lighting value at the specified block position for the specified lighting buffer.
 * Assumes the caller is already holding the lock on this buffer on all neighbors.
 */
- (uint8_t)lightAtPoint:(GSIntegerVector3)p buffer:(SEL)buffer;

/* Executes the specified block while holding the specified lock (for reading) on for all chunks in the neighborhood. */
- (void)accessToChunkWithLock:(SEL)getter usingBlock:(void (^)(void))block lock:(SEL)lock unlock:(SEL)unlock;

/* Executes the specified block while holding the specified lock (for reading) on for all chunks in the neighborhood. */
- (void)readerAccessToChunkWithLock:(SEL)getter usingBlock:(void (^)(void))block;

/* Executes the specified block while holding the specified lock (for writing) on for all chunks in the neighborhood. */
- (void)writerAccessToChunkWithLock:(SEL)getter usingBlock:(void (^)(void))block;

/* Executes the specified block while holding the voxel data locks (for reading) on all chunks in the neighborhood. */
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Executes the specified block while holding the voxel data locks (for writing) on all chunks in the neighborhood. */
- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block;

/* Executes the specified block while holding the locks (for reading) on the specified lighting buffer,
 * for all chunks in the neighborhood.
 */
- (void)readerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block;

/* xecutes the specified block while holding the locks (for writing) on the specified lighting buffer,
 * for all chunks in the neighborhood.
 */
- (void)writerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block;

@end
