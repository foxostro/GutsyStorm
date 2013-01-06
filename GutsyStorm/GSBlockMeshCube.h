//
//  GSBlockMeshCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 12/27/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSBlockMesh.h"

@interface GSBlockMeshCube : NSObject <GSBlockGeometryGenerating>

- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP;

@end
