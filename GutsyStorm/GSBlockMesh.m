//
//  GSBlockMeshMesh.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSVertex.h"
#import "GSBuffer.h" // for buffer_element_t, needed by Voxel.h
#import "Voxel.h"
#import "GSFace.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"


@interface GSBlockMesh ()

- (void)rotateVertex:(struct vertex *)v quaternion:(GLKQuaternion *)quat;
- (NSArray *)transformVerticesForFace:(GSFace *)face upsideDown:(BOOL)upsideDown quatY_p:(GLKQuaternion *)quatY_p;
- (NSArray *)transformFaces:(NSArray *)faces direction:(voxel_dir_t)dir upsideDown:(BOOL)upsideDown;
- (face_t)transformCubeFaceEnum:(face_t)correspondingCubeFace upsideDown:(BOOL)upsideDown;

@end


@implementation GSBlockMesh
{
    NSArray *_faces[2][NUM_VOXEL_DIRECTIONS];
}

- (id)init
{
    self = [super init];
    if (self) {
        // nothing to do here
    }

    return self;
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

- (NSArray *)transformVerticesForFace:(GSFace *)face upsideDown:(BOOL)upsideDown quatY_p:(GLKQuaternion *)quatY_p
{
    assert(face);
    assert(quatY_p);
    assert(4 == [face.vertexList count]);
    
    NSMutableArray *transformedVertices = [[NSMutableArray alloc] initWithCapacity:[face.vertexList count]];

    NSEnumerator *enumerator = upsideDown ? [face.vertexList reverseObjectEnumerator] : [face.vertexList objectEnumerator];
    
    for(GSVertex *vertex in enumerator)
    {
        struct vertex v = vertex.v;
        
        if(upsideDown) {
            v.position[1] *= -1;
            v.normal[1] *= -1;
        }
        
        [self rotateVertex:&v quaternion:quatY_p];
        
        [transformedVertices addObject:[GSVertex vertexWithVertex:&v]];
    }
    
    return transformedVertices;
}

- (NSArray *)transformFaces:(NSArray *)faces direction:(voxel_dir_t)dir upsideDown:(BOOL)upsideDown
{
    GLKQuaternion quatY = quaternionForDirection(dir);
    NSUInteger faceCount = [faces count];
    NSMutableArray *transformedFaces = [[NSMutableArray alloc] initWithCapacity:faceCount];
    
    for(GSFace *face in faces)
    {
        NSArray *transformedVertices = [self transformVerticesForFace:face upsideDown:upsideDown quatY_p:&quatY];
        face_t faceDir = [self transformCubeFaceEnum:face.correspondingCubeFace upsideDown:upsideDown];
        
        [transformedFaces addObject:[GSFace faceWithVertices:transformedVertices correspondingCubeFace:faceDir]];
    }
    
    return transformedFaces;
}

- (face_t)transformCubeFaceEnum:(face_t)correspondingCubeFace upsideDown:(BOOL)upsideDown
{
    if(upsideDown) {
        if(correspondingCubeFace == FACE_TOP) {
            return FACE_BOTTOM;
        } else if(correspondingCubeFace == FACE_BOTTOM) {
            return FACE_TOP;
        } else {
            return correspondingCubeFace;
        }
    } else {
        return correspondingCubeFace;
    }
}

- (void)setFaces:(NSArray *)faces
{
    for(int upsideDown = 0; upsideDown < 2; ++upsideDown)
    {
        for(voxel_dir_t dir = 0; dir < NUM_VOXEL_DIRECTIONS; ++dir)
        {
            _faces[upsideDown][dir] = [self transformFaces:faces direction:dir upsideDown:upsideDown];
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
    voxel_t voxel = [[voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER] voxelAtLocalPosition:chunkLocalPos];

    for(GSFace *face in _faces[voxel.upsideDown?1:0][voxel.dir])
    {
        // Omit the face if the face is eligible for such omission and is adjacent to a cube block.
        if(face.eligibleForOmission &&
           [voxelData voxelAtPoint:GSIntegerVector3_Add(chunkLocalPos,
                                                        offsetForFace[face.correspondingCubeFace])].type == VOXEL_TYPE_CUBE) {
            continue;
        }

        for(GSVertex *vertex in face.vertexList)
        {
            struct vertex v = vertex.v;
            
            v.position[0] += pos.v[0];
            v.position[1] += pos.v[1];
            v.position[2] += pos.v[2];

            // Grass and dirt are handled specially because it uses two textures and the others use one.
            if(voxel.tex == VOXEL_TEX_DIRT || voxel.tex == VOXEL_TEX_GRASS) {
                if(!voxel.exposedToAirOnTop && (v.texCoord[2] == VOXEL_TEX_GRASS || v.texCoord[2] == VOXEL_TEX_SIDE)) {
                    v.texCoord[2] = VOXEL_TEX_DIRT;
                }
            } else {
                v.texCoord[2] = voxel.tex;
            }

            [vertexList addObject:[GSVertex vertexWithVertex:&v]];
        }
    }
}

@end
