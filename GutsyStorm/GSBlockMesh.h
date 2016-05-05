//
//  GSBlockMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

@class GSFace;
@class GSBoxedTerrainVertex;
@class GSVoxelNeighborhood;

@interface GSBlockMesh : NSObject

- (void)setFaces:(nonnull NSArray<GSFace *> *)faces;

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(nonnull NSMutableArray<GSBoxedTerrainVertex *> *)vertexList
                                       voxelData:(nonnull GSVoxelNeighborhood *)voxelData
                                            minP:(vector_float3)minP;

@end