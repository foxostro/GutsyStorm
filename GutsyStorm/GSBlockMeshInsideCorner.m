//
//  GSBlockMeshInsideCorner.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/31/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSFace.h"
#import "GSVertex.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMeshMesh.h"
#import "GSBlockMeshInsideCorner.h"

@implementation GSBlockMeshInsideCorner

- (id)init
{
    self = [super init];
    if (self) {
        const static GLfloat L = 0.5f; // half the length of a block along one side

        [self setFaces:@[
            // Top (ramp surface)
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(-L, +L, -L)
                                                             normal:GSIntegerVector3_Make(0, 1, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_GRASS)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, +L, +L)
                                                             normal:GSIntegerVector3_Make(0, 1, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 0, VOXEL_TEX_GRASS)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, +L, +L)
                                                             normal:GSIntegerVector3_Make(0, 1, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_GRASS)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, 0, -1)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_GRASS)]]
               correspondingCubeFace:FACE_TOP],

            // Bottom
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(-L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, -1, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 0, VOXEL_TEX_DIRT)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, -1, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_DIRT)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, +L)
                                                             normal:GSIntegerVector3_Make(0, -1, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_DIRT)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, -L, +L)
                                                             normal:GSIntegerVector3_Make(0, -1, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_DIRT)]]
               correspondingCubeFace:FACE_BOTTOM],

            // Side A (a triangle)
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(+L, +L, +L)
                                                             normal:GSIntegerVector3_Make(1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, +L)
                                                             normal:GSIntegerVector3_Make(1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_RIGHT],

            // Side B (a triangle)
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, 0, -1)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, 0, -1)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, -L, -L)
                                                             normal:GSIntegerVector3_Make(0, 0, -1)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, +L, -L)
                                                             normal:GSIntegerVector3_Make(0, 0, -1)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_FRONT],

            // Side C (a full square)
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(-L, +L, -L)
                                                             normal:GSIntegerVector3_Make(-1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 0, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, -L, -L)
                                                             normal:GSIntegerVector3_Make(-1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, -L, +L)
                                                             normal:GSIntegerVector3_Make(-1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, +L, +L)
                                                             normal:GSIntegerVector3_Make(-1, 0, 0)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_LEFT],

            // Side D (a full square)
            [GSFace faceWithVertices:@[[GSVertex vertexWithPosition:GLKVector3Make(-L, +L, +L)
                                                             normal:GSIntegerVector3_Make(0, 0, +1)
                                                           texCoord:GSIntegerVector3_Make(0, 0, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(-L, -L, +L)
                                                             normal:GSIntegerVector3_Make(0, 0, +1)
                                                           texCoord:GSIntegerVector3_Make(0, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, -L, +L)
                                                             normal:GSIntegerVector3_Make(0, 0, +1)
                                                           texCoord:GSIntegerVector3_Make(1, 1, VOXEL_TEX_SIDE)],
                                       [GSVertex vertexWithPosition:GLKVector3Make(+L, +L, +L)
                                                             normal:GSIntegerVector3_Make(0, 0, +1)
                                                           texCoord:GSIntegerVector3_Make(1, 0, VOXEL_TEX_SIDE)]]
               correspondingCubeFace:FACE_BACK]
         ]];
    }
    
    return self;
}

@end
