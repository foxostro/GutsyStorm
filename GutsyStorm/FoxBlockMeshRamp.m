//
//  FoxBlockMeshRamp.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/27/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import "GSBoxedTerrainVertex.h"
#import "FoxTerrainBuffer.h" // for terrain_buffer_element_t, needed by Voxel.h
#import "FoxVoxel.h"
#import "FoxFace.h"
#import "FoxNeighborhood.h"
#import "FoxChunkVoxelData.h"
#import "FoxBlockMesh.h"
#import "FoxBlockMeshRamp.h"

@implementation FoxBlockMeshRamp

- (instancetype)init
{
    self = [super init];
    if (self) {
        const static GLfloat L = 0.5f; // half the length of a block along one side

        [self setFaces:@[
             // Top (ramp surface)
             [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                          normal:GSMakeIntegerVector3(0, 0, -1)
                                                        texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_GRASS)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, +L, +L)
                                                          normal:GSMakeIntegerVector3(0, +1, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_GRASS)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, +L, +L)
                                                          normal:GSMakeIntegerVector3(0, +1, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_GRASS)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, -L)
                                                          normal:GSMakeIntegerVector3(0, 0, -1)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_GRASS)]]
            correspondingCubeFace:FACE_TOP],
             
             // Bottom
             [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                          normal:GSMakeIntegerVector3(0, -1, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_DIRT)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, -L)
                                                          normal:GSMakeIntegerVector3(0, -1, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_DIRT)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                          normal:GSMakeIntegerVector3(0, -1, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_DIRT)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                          normal:GSMakeIntegerVector3(0, -1, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_DIRT)]]
            correspondingCubeFace:FACE_BOTTOM],
             
             // Back
             [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                          normal:GSMakeIntegerVector3(0, 0, +1)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                          normal:GSMakeIntegerVector3(0, 0, +1)
                                                        texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, +L, +L)
                                                          normal:GSMakeIntegerVector3(0, 0, +1)
                                                        texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, +L, +L)
                                                          normal:GSMakeIntegerVector3(0, 0, +1)
                                                        texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_SIDE)]]
            correspondingCubeFace:FACE_BACK],
             
             // Side A
             [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, +L, +L)
                                                          normal:GSMakeIntegerVector3(1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                          normal:GSMakeIntegerVector3(1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, -L)
                                                          normal:GSMakeIntegerVector3(1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, -L)
                                                          normal:GSMakeIntegerVector3(1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)]]
            correspondingCubeFace:FACE_RIGHT],
             
             // Side B
             [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                          normal:GSMakeIntegerVector3(-1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                          normal:GSMakeIntegerVector3(-1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                          normal:GSMakeIntegerVector3(-1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_SIDE)],
                                    [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, +L, +L)
                                                          normal:GSMakeIntegerVector3(-1, 0, 0)
                                                        texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_SIDE)]]
            correspondingCubeFace:FACE_LEFT]
         ]];
    }

    return self;
}

@end