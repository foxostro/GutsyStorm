//
//  GSNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxIntegerVector3.h"
#import "GSReaderWriterLock.h"
#import "GSVoxel.h"


@class GSChunkVoxelData;
@class GSTerrainBuffer;


@interface GSNeighborhood : NSObject

+ (vector_float3)offsetForNeighborIndex:(GSVoxelNeighborIndex)idx;

- (nonnull GSChunkVoxelData *)neighborAtIndex:(GSVoxelNeighborIndex)idx;
- (void)setNeighborAtIndex:(GSVoxelNeighborIndex)idx neighbor:(nonnull GSChunkVoxelData *)neighbor;
- (void)enumerateNeighborsWithBlock:(void (^ _Nonnull)(GSChunkVoxelData * _Nonnull voxels))block;
- (void)enumerateNeighborsWithBlock2:(void (^ _Nonnull)(GSVoxelNeighborIndex i, GSChunkVoxelData * _Nonnull voxels))block;

/* Copy the voxel data for this neighborhood into a new buffer and return that buffer.
 * The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and may be indexed using the INDEX2 macro.
 */
- (nonnull GSVoxel *)newVoxelBufferFromNeighborhood;

/* Given a position relative to this voxel, return the chunk that contains the specified position.
 * Also returns the position in the local coordinate system of that chunk.
 * The position must be within the neighborhood.
 */
- (nonnull GSChunkVoxelData *)neighborVoxelAtPoint:(nonnull vector_long3 *)chunkLocalP;

/* Returns a copy of the voxel at the the specified position in the neighborhood.
 * Positions are specified in chunk-local space relative to the center chunk of the neighborhood.
 * Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 */
- (GSVoxel)voxelAtPoint:(vector_long3)p;

/* Returns the lighting value at the specified block position for the specified lighting buffer. */
- (unsigned)lightAtPoint:(vector_long3)p
                  getter:(GSTerrainBuffer * _Nonnull (^ _Nonnull)(GSChunkVoxelData *  _Nonnull c))getter;

@end