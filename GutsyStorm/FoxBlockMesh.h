//
//  FoxBlockMeshMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

@class FoxFace;

@interface FoxBlockMesh : NSObject

- (void)setFaces:(nonnull NSArray<FoxFace *> *)faces;

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(nonnull NSMutableArray<GSBoxedTerrainVertex *> *)vertexList
                                       voxelData:(nonnull FoxNeighborhood *)voxelData
                                            minP:(vector_float3)minP;

@end