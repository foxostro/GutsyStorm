//
//  GSBlockMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

@class GSFace;

@interface GSBlockMesh : NSObject

- (void)setFaces:(nonnull NSArray<GSFace *> *)faces;

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(nonnull NSMutableArray<GSBoxedTerrainVertex *> *)vertexList
                                       voxelData:(nonnull GSNeighborhood *)voxelData
                                            minP:(vector_float3)minP;

@end