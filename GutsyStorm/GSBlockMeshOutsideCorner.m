//
//  GSBlockMeshOutsideCorner.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/31/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSVertex.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshMesh.h"
#import "GSBlockMeshOutsideCorner.h"

@implementation GSBlockMeshOutsideCorner

- (id)init
{
    self = [super init];
    if (self) {
        const static GLfloat L = 0.5f; // half the length of a block along one side

        const static struct vertex _mesh[] =
        {
            // Top (ramp surface)
            {
                {-L, -L, -L},           // position
                {0, 0, 0},              // color
                {0, 0, -1},             // normal
                {1, 1, VOXEL_TEX_GRASS} // texCoord
            },
            {
                {-L, +L, +L},           // position
                {0, 0, 0},              // color
                {0, +1, 0},             // normal
                {1, 0, VOXEL_TEX_GRASS} // texCoord
            },
            {
                {+L, -L, +L},           // position
                {0, 0, 0},              // color
                {0, 0, -1},             // normal
                {0, 0, VOXEL_TEX_GRASS} // texCoord
            },
            {
                {+L, -L, +L},           // position
                {0, 0, 0},              // color
                {0, 0, -1},             // normal
                {0, 0, VOXEL_TEX_GRASS} // texCoord
            },

            // Bottom
            {
                {+L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {0, 0, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {+L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {0, 0, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, +1, 0},            // normal
                {1, 0, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, -L, -L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {1, 1, VOXEL_TEX_DIRT} // texCoord
            },

            // Side A (a triangle)
            {
                {-L, -L, -L},          // position
                {0, 0, 0},             // color
                {1, 0, 0},             // normal
                {1, 1, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, -L, -L},          // position
                {0, 0, 0},             // color
                {1, 0, 0},             // normal
                {1, 1, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, -L, +L},          // position
                {0, 0, 0},             // color
                {1, 0, 0},             // normal
                {0, 1, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, +L, +L},          // position
                {0, 0, 0},             // color
                {1, 0, 0},             // normal
                {0, 0, VOXEL_TEX_DIRT} // texCoord
            },

            // Side B (a triangle)
            {
                {-L, +L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {0, 0, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {-L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {0, 1, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {+L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {1, 1, VOXEL_TEX_DIRT} // texCoord
            },
            {
                {+L, -L, +L},          // position
                {0, 0, 0},             // color
                {0, 0, -1},            // normal
                {1, 1, VOXEL_TEX_DIRT} // texCoord
            },
        };

        [self copyVertices:_mesh count:(sizeof(_mesh)/sizeof(_mesh[0]))];
    }
    
    return self;
}

@end
