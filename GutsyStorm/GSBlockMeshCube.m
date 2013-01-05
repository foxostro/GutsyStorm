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
            {0, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {0, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, -L, -L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {0, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, -L, -L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {0, 1, VOXEL_TEX_SIDE}     // texCoord
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
            {1, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {0, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, +L, -L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {0, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, -L, +L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {1, 1, VOXEL_TEX_SIDE}     // texCoord
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
            {1, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, +L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {1, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, +L, +L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {1, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, +L, +L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {1, 0, VOXEL_TEX_SIDE}     // texCoord
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
            {0, 0, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, -L, -L},              // position
            {0, 0, 0},                 // color
            {0, 0, -1},                // normal
            {1, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {+L, -L, +L},              // position
            {0, 0, 0},                 // color
            {1, 0, 0},                 // normal
            {1, 1, VOXEL_TEX_SIDE}     // texCoord
        },
        {
            {-L, +L, -L},              // position
            {0, 0, 0},                 // color
            {-1, 0, 0},                // normal
            {0, 0, VOXEL_TEX_SIDE}     // texCoord
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
    BOOL exposedToAirOnTop = [voxelData voxelAtPoint:chunkLocalPos].exposedToAirOnTop;

    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        // Omit this face if the neighboring voxel in that direction is also a cube.
        if([voxelData voxelAtPoint:GSIntegerVector3_Add(chunkLocalPos, offsetForFace[i])].type != VOXEL_TYPE_CUBE) {
            for(size_t j=0; j<4; ++j)
            {
                struct vertex v = meshCube[j][i];

                // translate point within the world
                v.position[0] += pos.v[0];
                v.position[1] += pos.v[1];
                v.position[2] += pos.v[2];

                // Use the GRASS and SIDE textures if we previously determined they were necessary. Otherwise, use DIRT.
                // XXX: There's a very similar if statement in GSBlockMeshMesh. Can these be consolidated?
                if(!exposedToAirOnTop && (v.texCoord[2] == VOXEL_TEX_GRASS || v.texCoord[2] == VOXEL_TEX_SIDE)) {
                    v.texCoord[2] = VOXEL_TEX_DIRT;
                }

                [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v] autorelease]];
            }
        }
    }
}

@end
