//
//  GSBlockMeshOutsideCorner.h
//  GutsyStorm
//
//  Created by Andrew Fox on 12/31/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSBlockMeshOutsideCorner : NSObject <GSBlockMesh>

- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP;

@end
