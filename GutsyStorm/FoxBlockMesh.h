//
//  FoxBlockMeshMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

@interface FoxBlockMesh : NSObject

- (void)setFaces:(NSArray *)faces;

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(FoxNeighborhood *)voxelData
                                            minP:(vector_float3)minP;

@end
