//
//  GSBlockMeshOutsideCorner.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/31/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import "GSTerrainBuffer.h" // for terrain_buffer_element_t, needed by Voxel.h
#import "GSVoxel.h"
#import "FoxFace.h"
#import "GSBoxedTerrainVertex.h"
#import "FoxNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshOutsideCorner.h"

@implementation GSBlockMeshOutsideCorner

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
                                       [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                             normal:GSMakeIntegerVector3(0, 0, -1)
                                                           texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_GRASS)],
                                       [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                             normal:GSMakeIntegerVector3(0, 0, -1)
                                                           texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_GRASS)]]
               correspondingCubeFace:FACE_TOP],

            // Bottom
            [FoxFace faceWithQuad:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                             normal:GSMakeIntegerVector3(0, -1, 0)
                                                           texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_DIRT)],
                                       [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                             normal:GSMakeIntegerVector3(0, -1, 0)
                                                           texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_DIRT)],
                                       [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                             normal:GSMakeIntegerVector3(0, -1, 0)
                                                           texCoord:GSMakeIntegerVector3(1, 0, VOXEL_TEX_DIRT)],
                                       [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                             normal:GSMakeIntegerVector3(0, -1, 0)
                                                           texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_DIRT)]]
               correspondingCubeFace:FACE_BOTTOM],

            // Side A (a triangle)
            [FoxFace faceWithTri:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, -L)
                                                        normal:GSMakeIntegerVector3(1, 0, 0)
                                                      texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_SIDE)],
                                  [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                        normal:GSMakeIntegerVector3(1, 0, 0)
                                                      texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                  [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, +L, +L)
                                                        normal:GSMakeIntegerVector3(1, 0, 0)
                                                      texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_RIGHT],

            // Side B (a triangle)
            [FoxFace faceWithTri:@[[GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, +L, +L)
                                                        normal:GSMakeIntegerVector3(0, 0, -1)
                                                      texCoord:GSMakeIntegerVector3(0, 0, VOXEL_TEX_SIDE)],
                                  [GSBoxedTerrainVertex vertexWithPosition:vector_make(-L, -L, +L)
                                                        normal:GSMakeIntegerVector3(0, 0, -1)
                                                      texCoord:GSMakeIntegerVector3(0, 1, VOXEL_TEX_SIDE)],
                                  [GSBoxedTerrainVertex vertexWithPosition:vector_make(+L, -L, +L)
                                                        normal:GSMakeIntegerVector3(0, 0, -1)
                                                      texCoord:GSMakeIntegerVector3(1, 1, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_FRONT]
         ]];
    }
    
    return self;
}

@end
