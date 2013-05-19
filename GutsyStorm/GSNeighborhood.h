//
//  GSNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSReaderWriterLock.h"
#import "Voxel.h"


@class GSChunkVoxelData;
@class GSBuffer;


// Moore neighborhood of voxel cells (in three dimensions)
@interface GSNeighborhood : NSObject

- (id)initWithCenterPoint:(GLKVector3)centerMinP chunkProducer:(GSChunkVoxelData * (^)(GLKVector3 p))chunkProducer;

- (GSChunkVoxelData *)neighborAtPosition:(GSNeighborOffset)positionInNeighborhood;

- (void)enumerateNeighborsWithBlock:(void (^)(GSChunkVoxelData *voxels))block;
- (void)enumerateNeighborsWithBlock2:(void (^)(GSNeighborOffset positionInNeighborhood, GSChunkVoxelData *voxels))block;

/* Copy the voxel data for this neighborhood into a new buffer and return that buffer.
 * The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and may be indexed using the INDEX2 macro.
 */
- (voxel_t *)newVoxelBufferFromNeighborhood;

/* Returns a copy of the voxel at the the specified position in the neighborhood.
 * Positions are specified in chunk-local space relative to the center chunk of the neighborhood.
 * Coordinates which exceed the bounds of the center chunk refer to its neighbors.
 */
- (voxel_t)voxelAtPoint:(GSIntegerVector3)p;

/* Returns the lighting value at the specified block position for the specified lighting buffer. */
- (unsigned)lightAtPoint:(GSIntegerVector3)p getter:(GSBuffer* (^)(GSChunkVoxelData *c))getter;

@end
