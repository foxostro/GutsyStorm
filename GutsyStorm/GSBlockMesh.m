//
//  GSBlockMesh.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/1/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSBoxedTerrainVertex.h"
#import "GSTerrainBuffer.h" // for GSTerrainBufferElement, needed by Voxel.h
#import "GSVoxel.h"
#import "GSFace.h"
#import "GSVoxelNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"


@interface GSBlockMesh ()

- (void)rotateVertex:(GSTerrainVertex *)v quaternion:(vector_float4)quat;
- (nonnull NSArray<GSBoxedTerrainVertex *> *)transformVerticesForFace:(nonnull GSFace *)face
                                                           upsideDown:(BOOL)upsideDown
                                                                quatY:(vector_float4)quatY;
- (nonnull NSArray<GSFace *> *)transformFaces:(nonnull NSArray<GSFace *> *)faces
                                    direction:(GSVoxelDirection)dir
                                   upsideDown:(BOOL)upsideDown;
- (GSVoxelFace)transformCubeFaceEnum:(GSVoxelFace)correspondingCubeFace
                           direction:(GSVoxelDirection)dir
                          upsideDown:(BOOL)upsideDown;

@end


@implementation GSBlockMesh
{
    NSArray<GSFace *> *_faces[2][NUM_VOXEL_DIRECTIONS];
}

- (nonnull instancetype)init
{
    self = [super init];
    if (self) {
        // nothing to do here
    }

    return self;
}

- (void)rotateVertex:(nonnull GSTerrainVertex *)v quaternion:(vector_float4)quat
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

- (nonnull NSArray<GSBoxedTerrainVertex *> *)transformVerticesForFace:(nonnull GSFace *)face
                                                           upsideDown:(BOOL)upsideDown
                                                                quatY:(vector_float4)quatY
{
    assert(face);

    NSArray<GSBoxedTerrainVertex *> *vertexList = face.vertexList;
    NSUInteger count = [vertexList count];
    NSMutableArray<GSBoxedTerrainVertex *> *transformedVertices = [[NSMutableArray<GSBoxedTerrainVertex *> alloc] initWithCapacity:count];

    NSEnumerator *enumerator = upsideDown ? [vertexList reverseObjectEnumerator] : [vertexList objectEnumerator];

    for(GSBoxedTerrainVertex *vertex in enumerator)
    {
        GSTerrainVertex v = vertex.v;

        if (upsideDown) {
            v.position[1] *= -1;
            v.normal[1] *= -1;
        }

        [self rotateVertex:&v quaternion:quatY];

        [transformedVertices addObject:[GSBoxedTerrainVertex vertexWithVertex:&v]];
    }

    return transformedVertices;
}

- (nonnull NSArray<GSFace *> *)transformFaces:(nonnull NSArray<GSFace *> *)faces
                                    direction:(GSVoxelDirection)dir
                                   upsideDown:(BOOL)upsideDown
{
    vector_float4 quatY = GSQuaternionForVoxelDirection(dir);
    NSUInteger faceCount = [faces count];
    NSMutableArray<GSFace *> *transformedFaces = [[NSMutableArray<GSFace *> alloc] initWithCapacity:faceCount];

    for(GSFace *face in faces)
    {
        NSArray<GSBoxedTerrainVertex *> *transformedVertices = [self transformVerticesForFace:face
                                                                        upsideDown:upsideDown
                                                                             quatY:quatY];
        GSVoxelFace faceDir = [self transformCubeFaceEnum:face.correspondingCubeFace
                                                direction:dir
                                               upsideDown:upsideDown];
        GSFace *transformedFace = [[GSFace alloc] initWithVertices:transformedVertices
                                             correspondingCubeFace:faceDir
                                               eligibleForOmission:face.eligibleForOmission];
        [transformedFaces addObject:transformedFace];
    }

    return transformedFaces;
}

- (GSVoxelFace)transformCubeFaceEnum:(GSVoxelFace)correspondingCubeFace
                           direction:(GSVoxelDirection)dir
                          upsideDown:(BOOL)upsideDown
{
    GSVoxelFace transformedFace;

    if(correspondingCubeFace == FACE_TOP) {
        transformedFace = upsideDown ? FACE_BOTTOM : FACE_TOP;
    } else if(correspondingCubeFace == FACE_BOTTOM) {
        transformedFace = upsideDown ? FACE_TOP : FACE_BOTTOM;
    } else {
        GSVoxelFace face[FACE_NUM_FACES][NUM_VOXEL_DIRECTIONS] = {
            {0},
            {0},
            {FACE_BACK,  FACE_RIGHT, FACE_FRONT, FACE_LEFT},  // BACK
            {FACE_FRONT, FACE_LEFT,  FACE_BACK,  FACE_RIGHT}, // FRONT
            {FACE_RIGHT, FACE_FRONT, FACE_LEFT,  FACE_BACK},  // RIGHT
            {FACE_LEFT,  FACE_BACK,  FACE_RIGHT, FACE_FRONT}, // LEFT
        };
        transformedFace = face[correspondingCubeFace][dir];
    }
    
    return transformedFace;
}

- (void)setFaces:(nonnull NSArray<GSFace *> *)faces
{
    for(int upsideDown = 0; upsideDown < 2; ++upsideDown)
    {
        for(GSVoxelDirection dir = 0; dir < NUM_VOXEL_DIRECTIONS; ++dir)
        {
            _faces[upsideDown][dir] = [self transformFaces:faces direction:dir upsideDown:upsideDown];
        }
    }
}

- (void)generateGeometryForSingleBlockAtPosition:(vector_float3)pos
                                      vertexList:(nonnull NSMutableArray<GSBoxedTerrainVertex *> *)vertexList
                                       voxelData:(nonnull GSVoxelNeighborhood *)voxelData
                                            minP:(vector_float3)minP
{
    assert(vertexList);
    assert(voxelData);

    vector_long3 chunkLocalPos = GSMakeIntegerVector3(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    GSVoxel voxel = [[voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER] voxelAtLocalPosition:chunkLocalPos];

    for(GSFace *face in _faces[voxel.upsideDown?1:0][voxel.dir])
    {
        // Some faces are marked as being eligible for omission. These faces are generally unit squares which are
        // aligned with the faces of the basic axis-aligned cube for the block. These faces can be omitted when this
        // voxel directly abuts a cube block.
        if(face.eligibleForOmission && [voxelData voxelAtPoint:(chunkLocalPos + GSOffsetForVoxelFace[face.correspondingCubeFace])].type == VOXEL_TYPE_CUBE) {
            continue;
        }

        for(GSBoxedTerrainVertex *vertex in face.vertexList)
        {
            GSTerrainVertex v = vertex.v;
            
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

            [vertexList addObject:[GSBoxedTerrainVertex vertexWithVertex:&v]];
        }
    }
}

@end
