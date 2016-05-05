//
//  GSVoxelNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSNeighborhood.h"
#import "GSVoxel.h"
#import "GSChunkVoxelData.h"

@interface GSVoxelNeighborhood : GSNeighborhood<GSChunkVoxelData *>

/* Given a position relative to this voxel, return the chunk that contains the specified position.
 * Also returns the position in the local coordinate system of that chunk.
 * The position must be within the neighborhood.
 */
- (nonnull GSChunkVoxelData *)neighborVoxelAtPoint:(nonnull vector_long3 *)chunkLocalPos;

/* Returns a copy of the voxel at the the specified position in the neighborhood.
 * Positions are specified in chunk-local space relative to the center chunk of the neighborhood.
 * Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 */
- (GSVoxel)voxelAtPoint:(vector_long3)p;

/* Return a buffer containing the voxel data for all neighbors in the neighborhood.
 * Use `outCount' to return the count of elements in the buffer.
 * It is the responsibility of the caller to free this memory.
 */
- (nonnull GSVoxel *)newVoxelBufferReturningCount:(nullable size_t *)outCount;

/* Generate and return sunlight data for the center chunk of the voxel neighborhood. */
- (nonnull GSTerrainBuffer *)newSunlightBuffer;

@end
