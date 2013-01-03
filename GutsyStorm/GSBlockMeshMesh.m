//
//  GSBlockMeshMesh.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSVertex.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshMesh.h"

@implementation GSBlockMeshMesh

- (id)init
{
    self = [super init];
    if (self) {
        numVertices = 0;
        vertices = NULL;
    }

    return self;
}

- (void)dealloc
{
    free(vertices);
    [super dealloc];
}

- (void)copyVertices:(const struct vertex*)mesh count:(NSUInteger)count
{
    numVertices = count;
    assert(numVertices % 4 == 0);
    const size_t len = sizeof(struct vertex) * numVertices;
    vertices = memcpy(malloc(len), mesh, len);
}

- (void)rotateVertex:(struct vertex *)v quaternion:(GLKQuaternion *)quat
{
    GLKVector3 vertexPos, normal;

    vertexPos = GLKVector3Make(v->position[0], v->position[1], v->position[2]);
    vertexPos = GLKQuaternionRotateVector3(*quat, vertexPos);
    v->position[0] = vertexPos.v[0];
    v->position[1] = vertexPos.v[1];
    v->position[2] = vertexPos.v[2];

    normal = GLKVector3Make(v->normal[0], v->normal[1], v->normal[2]);
    normal = GLKQuaternionRotateVector3(*quat, normal);
    v->normal[0] = normal.v[0];
    v->normal[1] = normal.v[1];
    v->normal[2] = normal.v[2];
}

- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP
{
    assert(vertexList);
    assert(voxelData);

    GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    GSChunkVoxelData *centerVoxels = [voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    voxel_t voxel = [centerVoxels voxelAtLocalPosition:chunkLocalPos];
    GLKQuaternion quatY = quaternionForDirection(voxel.dir);

    assert(numVertices % 4 == 0);

    for(size_t i = 0; i < numVertices; ++i)
    {
        struct vertex v = vertices[i];

        if(voxel.upsideDown) {
            v.position[1] *= -1;
            v.normal[1] *= -1;
        }

        [self rotateVertex:&v quaternion:&quatY];

        v.position[0] += pos.v[0];
        v.position[1] += pos.v[1];
        v.position[2] += pos.v[2];

        // TODO: cubes which are exposed to air on top should also use the SIDE texture.
        if(!voxel.exposedToAirOnTop && (v.texCoord[2] == VOXEL_TEX_GRASS || v.texCoord[2] == VOXEL_TEX_SIDE)) {
            v.texCoord[2] = VOXEL_TEX_DIRT;
        }
        
        [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v] autorelease]];
    }
}

@end
