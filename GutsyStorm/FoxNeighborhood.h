//
//  FoxNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxIntegerVector3.h"
#import "FoxReaderWriterLock.h"
#import "FoxVoxel.h"


@class FoxChunkVoxelData;
@class FoxTerrainBuffer;


@interface FoxNeighborhood : NSObject

+ (vector_float3)offsetForNeighborIndex:(neighbor_index_t)idx;

- (FoxChunkVoxelData *)neighborAtIndex:(neighbor_index_t)idx;
- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(FoxChunkVoxelData *)neighbor;
- (void)enumerateNeighborsWithBlock:(void (^)(FoxChunkVoxelData *voxels))block;
- (void)enumerateNeighborsWithBlock2:(void (^)(neighbor_index_t i, FoxChunkVoxelData *voxels))block;

/* Copy the voxel data for this neighborhood into a new buffer and return that buffer.
 * The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and may be indexed using the INDEX2 macro.
 */
- (voxel_t *)newVoxelBufferFromNeighborhood;

/* Given a position relative to this voxel, return the chunk that contains the specified position.
 * Also returns the position in the local coordinate system of that chunk.
 * The position must be within the neighborhood.
 */
- (FoxChunkVoxelData *)neighborVoxelAtPoint:(vector_long3 *)chunkLocalP;

/* Returns a copy of the voxel at the the specified position in the neighborhood.
 * Positions are specified in chunk-local space relative to the center chunk of the neighborhood.
 * Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 */
- (voxel_t)voxelAtPoint:(vector_long3)p;

/* Returns the lighting value at the specified block position for the specified lighting buffer. */
- (unsigned)lightAtPoint:(vector_long3)p getter:(FoxTerrainBuffer* (^)(FoxChunkVoxelData *c))getter;

@end
