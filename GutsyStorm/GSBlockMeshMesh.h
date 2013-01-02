//
//  GSBlockMeshMesh.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSBlockMeshMesh : NSObject <GSBlockMesh>
{
    size_t numVertices;
    struct vertex *vertices;
}

- (void)copyVertices:(const struct vertex*)mesh count:(NSUInteger)count;

- (void)rotateVertex:(struct vertex *)v quaternion:(GLKQuaternion *)quat;

- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP;

@end
