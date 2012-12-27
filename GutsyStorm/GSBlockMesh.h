//
//  GSBlockMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 12/26/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSNeighborhood;

@protocol GSBlockMesh <NSObject>

/* Generates geometry for the block at the specified position. For each new vertex, this method
 * adds a vertex to vertsBuffer.
 *
 * pos - World space position of the block.
 * vertsBuffer - Buffer for vertices being added to the chunk.
 * voxelData - Information on the block and the neighboring blocks.
 * minP - Position of the minimum corner of the chunk.
 *
 * Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight.lockLightingBuffer" for the center chunk in the neighborhood (for reading).
 */
- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP;

@end
