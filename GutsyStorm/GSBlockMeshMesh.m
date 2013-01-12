//
//  GSBlockMeshMesh.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSVertex.h"
#import "GSFace.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshMesh.h"

@interface GSBlockMeshMesh ()

- (void)rotateVertex:(struct vertex *)v quaternion:(GLKQuaternion *)quat;

@end


@implementation GSBlockMeshMesh
{
    size_t _numVertices;
    struct vertex *_vertices[NUM_VOXEL_DIRECTIONS];
    struct vertex *_upsideDownVertices[NUM_VOXEL_DIRECTIONS];
}

- (id)init
{
    self = [super init];
    if (self) {
        // nothing to do here
    }

    return self;
}

- (void)dealloc
{
    for(voxel_dir_t dir = 0; dir < NUM_VOXEL_DIRECTIONS; ++dir)
    {
        free(_vertices[dir]);
        free(_upsideDownVertices[dir]);
    }
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

- (void)setFaces:(NSArray *)faces
{
    assert(faces);
    
    _numVertices = 4 * [faces count];

    assert(_numVertices>0);
    assert(_numVertices % 4 == 0);

    for(voxel_dir_t dir = 0; dir < NUM_VOXEL_DIRECTIONS; ++dir)
    {
        GLKQuaternion quatY = quaternionForDirection(dir);
        struct vertex *vertices = _vertices[dir] = calloc(_numVertices, sizeof(struct vertex));
        struct vertex *upsideDownVertices = _upsideDownVertices[dir] = calloc(_numVertices, sizeof(struct vertex));

        for(GSFace *face in faces)
        {
            assert(4 == [face.vertexList count]);
            for(GSVertex *vertex in face.vertexList)
            {
                struct vertex v = vertex.v;
                [self rotateVertex:&v quaternion:&quatY];
                *vertices++ = v;
            }

            assert(4 == [face.reversedVertexList count]);
            for(GSVertex *vertex in face.reversedVertexList)
            {
                struct vertex v = vertex.v;
                v.position[1] *= -1;
                v.normal[1] *= -1;
                [self rotateVertex:&v quaternion:&quatY];
                *upsideDownVertices++ = v;
            }
        }
    }
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
    struct vertex *vertices = (voxel.upsideDown ? _upsideDownVertices : _vertices)[voxel.dir];

    assert(vertices);
    assert(numVertices % 4 == 0);

    for(size_t i = 0; i < _numVertices; ++i)
    {
        struct vertex v = vertices[i];

        v.position[0] += pos.v[0];
        v.position[1] += pos.v[1];
        v.position[2] += pos.v[2];

        if(!voxel.exposedToAirOnTop && (v.texCoord[2] == VOXEL_TEX_GRASS || v.texCoord[2] == VOXEL_TEX_SIDE)) {
            v.texCoord[2] = VOXEL_TEX_DIRT;
        }
        
        [vertexList addObject:[[GSVertex alloc] initWithVertex:&v]];
    }
}

@end
