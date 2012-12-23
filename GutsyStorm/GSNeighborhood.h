//
//  GSGridNeighbors.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSReaderWriterLock.h"


@class GSChunkVoxelData;
@class GSLightingBuffer;


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
+ (GLKVector3)offsetForNeighborIndex:(neighbor_index_t)idx;

- (GSChunkVoxelData *)neighborAtIndex:(neighbor_index_t)idx;
- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(GSChunkVoxelData *)neighbor;
- (void)enumerateNeighborsWithBlock:(void (^)(GSChunkVoxelData *voxels))block;
- (void)enumerateNeighborsWithBlock2:(void (^)(neighbor_index_t i, GSChunkVoxelData *voxels))block;

/* Given a position relative to this voxel, return the chunk that contains the specified position.
 * Also returns the position in the local coordinate system of that chunk.
 * The position must be within the neighborhood.
 */
- (GSChunkVoxelData *)neighborVoxelAtPoint:(GSIntegerVector3 *)chunkLocalP;

/* Returns YES if the specified block in the neighborhood is empty. Positions are specified in chunk-local space relative to the
 * center chunk of the neighborhood. Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 * Assumes the caller is already holding "lockVoxelData" on all chunks in the neighborhood.
 */
- (BOOL)emptyAtPoint:(GSIntegerVector3)p;

/* Returns the lighting value at the specified block position for the specified lighting buffer.
 * Assumes the caller is already holding the lock on this buffer on all neighbors.
 */
- (uint8_t)lightAtPoint:(GSIntegerVector3)p getter:(GSLightingBuffer* (^)(GSChunkVoxelData *c))getter;

- (BOOL)tryReaderAccessToVoxelDataUsingBlock:(void (^)(void))block;
- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block;

@end
