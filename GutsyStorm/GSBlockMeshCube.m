//
//  GSBlockMeshCube.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/27/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSBlockMeshCube.h"
#import "GSVertex.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"

const static GLfloat L = 0.5f; // half the length of a block along one side

const static struct vertex meshCube[4][FACE_NUM_FACES] =
{
    {
        {
            {-L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 1, 0},                 // normal
            {1, 1, VOXEL_TEX_GRASS}    // texCoord
        },
        {
            {-L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, -1, 0},                // normal
            {1, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, -L, +L},              // position
            {0, 0, 0},                 // color
            {0, 0, 1},                 // normal
            {0, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {0, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, -L, -L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {0, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, -L, -L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {0, 1, VOXEL_TEX_DIRT}     // texCoord
        }
    },
    {
        {
            {-L, +L, +L},              // position
            {0, 0, 0},                 // color
            {0, 1, 0},                 // normal
            {1, 0, VOXEL_TEX_GRASS}    // texCoord
        },
        {
            {+L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, -1, 0},                // normal
            {0, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, -L, +L},              // position
            {0, 0, 0},                 // color
            {0, 0, 1},                 // normal
            {1, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {0, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, +L, -L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {0, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, -L, +L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {1, 1, VOXEL_TEX_DIRT}     // texCoord
        }
    },
    {
        {
            {+L, +L, +L},              // position
            {0, 0, 0},                 // color
            {0, 1, 0},                 // normal
            {0, 0, VOXEL_TEX_GRASS}    // texCoord
        },
        {
            {+L, -L, +L},              // position
            {0, 0, 0},                 // color
            {0, -1, 0},                // normal
            {0, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, +L, +L},              // position
            {0, 0, 0},                 // color
            {0, 0, 1},                 // normal
            {1, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {1, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, +L, +L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {1, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, +L, +L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {1, 0, VOXEL_TEX_DIRT}     // texCoord
        }
    },
    {
        {
            {+L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 1, 0},                 // normal
            {0, 1, VOXEL_TEX_GRASS}    // texCoord
        },
        {
            {-L, -L, +L},              // position
            {0, 0, 0},                 // color
            {0, -1, 0},                // normal
            {1, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, +L, +L},              // position
            {0, 0, 0},                 // color
            {0, 0, 1},                 // normal
            {0, 0, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {1, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {+L, -L, +L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {1, 1, VOXEL_TEX_DIRT}     // texCoord
        },
        {
            {-L, +L, -L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {0, 0, VOXEL_TEX_DIRT}     // texCoord
        }
    }
};

@implementation GSBlockMeshCube

- (id)init
{
    self = [super init];
    if (self) {
        // nothing to do
    }

    return self;
}

- (void)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                      vertexList:(NSMutableArray *)vertexList
                                       voxelData:(GSNeighborhood *)voxelData
                                            minP:(GLKVector3)minP
{
    assert(vertexList);
    assert(voxelData);

    GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);

    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        if([voxelData cubeAtPoint:GSIntegerVector3_Add(chunkLocalPos, offsetForFace[i])]) {
            continue;
        }

        for(size_t j=0; j<4; ++j)
        {
            struct vertex v = meshCube[j][i];

            // translate point within the world
            v.position[0] += pos.v[0];
            v.position[1] += pos.v[1];
            v.position[2] += pos.v[2];

            [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v] autorelease]];
        }
    }
}

@end
