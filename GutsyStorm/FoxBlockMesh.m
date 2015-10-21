//
//  FoxBlockMeshMesh.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "FoxVertex.h"
#import "FoxTerrainBuffer.h" // for terrain_buffer_element_t, needed by Voxel.h
#import "FoxVoxel.h"
#import "FoxFace.h"
#import "FoxNeighborhood.h"
#import "FoxChunkVoxelData.h"
#import "FoxBlockMesh.h"


@interface FoxBlockMesh ()

- (void)rotateVertex:(struct fox_vertex *)v quaternion:(vector_float4)quat;
- (NSArray<FoxVertex *> *)transformVerticesForFace:(FoxFace *)face
                                        upsideDown:(BOOL)upsideDown
                                             quatY:(vector_float4)quatY;
- (NSArray<FoxFace *> *)transformFaces:(NSArray<FoxFace *> *)faces
                             direction:(voxel_dir_t)dir
                            upsideDown:(BOOL)upsideDown;
- (face_t)transformCubeFaceEnum:(face_t)correspondingCubeFace upsideDown:(BOOL)upsideDown;

@end


@implementation FoxBlockMesh
{
    NSArray<FoxFace *> *_faces[2][NUM_VOXEL_DIRECTIONS];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // nothing to do here
    }

    return self;
}

- (void)rotateVertex:(struct fox_vertex *)v quaternion:(vector_float4)quat
{
    vector_float3 vertexPos, normal;

    vertexPos = vector_make(v->position[0], v->position[1], v->position[2]);
    vertexPos = quaternion_rotate_vector(quat, vertexPos);
    v->position[0] = vertexPos.x;
    v->position[1] = vertexPos.y;
    v->position[2] = vertexPos.z;

    normal = vector_make(v->normal[0], v->normal[1], v->normal[2]);
    normal = quaternion_rotate_vector(quat, normal);
    v->normal[0] = normal.x;
    v->normal[1] = normal.y;
    v->normal[2] = normal.z;
}

- (NSArray<FoxVertex *> *)transformVerticesForFace:(FoxFace *)face
                                        upsideDown:(BOOL)upsideDown
                                             quatY:(vector_float4)quatY
{
    assert(face);

    NSArray<FoxVertex *> *vertexList = face.vertexList;
    NSUInteger count = [vertexList count];
    NSMutableArray<FoxVertex *> *transformedVertices = [[NSMutableArray<FoxVertex *> alloc] initWithCapacity:count];

    NSEnumerator *enumerator = upsideDown ? [vertexList reverseObjectEnumerator] : [vertexList objectEnumerator];

    for(FoxVertex *vertex in enumerator)
    {
        struct fox_vertex v = vertex.v;

        if (upsideDown) {
            v.position[1] *= -1;
            v.normal[1] *= -1;
        }

        [self rotateVertex:&v quaternion:quatY];

        [transformedVertices addObject:[FoxVertex vertexWithVertex:&v]];
    }

    return transformedVertices;
}

- (NSArray<FoxFace *> *)transformFaces:(NSArray<FoxFace *> *)faces
                             direction:(voxel_dir_t)dir
                            upsideDown:(BOOL)upsideDown
{
    vector_float4 quatY = quaternionForDirection(dir);
    NSUInteger faceCount = [faces count];
    NSMutableArray<FoxFace *> *transformedFaces = [[NSMutableArray<FoxFace *> alloc] initWithCapacity:faceCount];
    
    for(FoxFace *face in faces)
    {
        NSArray<FoxVertex *> *transformedVertices = [self transformVerticesForFace:face
                                                                        upsideDown:upsideDown
                                                                             quatY:quatY];
        face_t faceDir = [self transformCubeFaceEnum:face.correspondingCubeFace upsideDown:upsideDown];
        FoxFace *transformedFace = [[FoxFace alloc] initWithVertices:transformedVertices
                                             correspondingCubeFace:faceDir
                                               eligibleForOmission:face.eligibleForOmission];
        [transformedFaces addObject:transformedFace];
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

- (void)setFaces:(NSArray<FoxFace *> *)faces
{
    for(int upsideDown = 0; upsideDown < 2; ++upsideDown)
    {
        for(voxel_dir_t dir = 0; dir < NUM_VOXEL_DIRECTIONS; ++dir)
        {
            _faces[upsideDown][dir] = [self transformFaces:faces direction:dir upsideDown:upsideDown];
        }
    }
}

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(NSMutableArray<FoxVertex *> *)vertexList
                                       voxelData:(FoxNeighborhood *)voxelData
                                            minP:(vector_float3)minP
{
    assert(vertexList);
    assert(voxelData);

    vector_long3 chunkLocalPos = fox_ivec3_make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    voxel_t voxel = [[voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER] voxelAtLocalPosition:chunkLocalPos];

    for(FoxFace *face in _faces[voxel.upsideDown?1:0][voxel.dir])
    {
        // Omit the face if the face is eligible for such omission and is adjacent to a cube block.
        // There are several configurations of several types of adjacent blocks that would permit faces to be omitted.
        // However, the logic for determining whether a face polygon is perfectly occluded by an adjacent block face
        // polygon is tricky. So, we're just going to skip that.
        if(face.eligibleForOmission && [voxelData voxelAtPoint:(chunkLocalPos + offsetForFace[face.correspondingCubeFace])].type == VOXEL_TYPE_CUBE) {
            continue;
        }

        for(FoxVertex *vertex in face.vertexList)
        {
            struct fox_vertex v = vertex.v;
            
            v.position[0] += pos.x;
            v.position[1] += pos.y;
            v.position[2] += pos.z;

            // Grass and dirt are handled specially because it uses two textures and the others use one.
            if(voxel.tex == VOXEL_TEX_DIRT || voxel.tex == VOXEL_TEX_GRASS) {
                if(!voxel.exposedToAirOnTop && (v.texCoord[2] == VOXEL_TEX_GRASS || v.texCoord[2] == VOXEL_TEX_SIDE)) {
                    v.texCoord[2] = VOXEL_TEX_DIRT;
                }
            } else {
                v.texCoord[2] = voxel.tex;
            }

            [vertexList addObject:[FoxVertex vertexWithVertex:&v]];
        }
    }
}

@end
