//
//  GSSunlightNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSVoxelNeighborhood.h"
#import "GSChunkSunlightData.h"

@interface GSSunlightNeighborhood : GSNeighborhood<GSChunkSunlightData *>

/* We allow a voxel neighborhood to be specified separately from the sunlight chunks in order to allow sunlight
 * calculations basd off a modified voxel neighborhood. Because sunlight chunks are immutable, this is otherwise not
 * possible.
 */
@property (nonatomic, nullable, retain) GSVoxelNeighborhood *voxelNeighborhood;

/* Generate and return sunlight data for the entire voxel neighborhood, taking into account a modification made at the
 * specified point. Leverages existing sunlight values in neighboring sunlight chunks to ensure that chunk sunlight is
 * correct for the entire neighborhood.
 */
- (nonnull GSTerrainBuffer *)newSunlightBufferWithEditAtPoint:(vector_float3)editPos
removingLight:(BOOL)mode
                                             affectedAreaMinP:(vector_long3 * _Nullable)affectedAreaMinP
                                             affectedAreaMaxP:(vector_long3 * _Nullable)affectedAreaMaxP;

@end
