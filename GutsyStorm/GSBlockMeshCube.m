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

const static GSIntegerVector3 test[FACE_NUM_FACES] = {
    {0, +1, 0},
    {0, -1, 0},
    {0, 0, +1},
    {0, 0, -1},
    {+1, 0, 0},
    {-1, 0, 0}
};

const static struct vertex meshCube[4][FACE_NUM_FACES] =
{
    {
        {
            {-L, +L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, 0},     // normal
            {1, 0, VOXEL_TEX_GRASS} // texCoord
        },
        {
            {-L, -L, -L},  // position
            {0, 0, 0},     // color
            {0, -1, 0},    // normal
            {1, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {
            {-L, -L, +L},  // position
            {0, 0, 0},     // color
            {0, 0, 1},     // normal
            {0, 1, -1}     // texCoord
        },
        {
            {-L, -L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, -1},    // normal
            {0, 1, -1}     // texCoord
        },
        {
            {+L, -L, -L},  // position
            {0, 0, 0},     // color
            {1, 0, 0},     // normal
            {0, 1, -1}     // texCoord
        },
        {
            {-L, -L, -L},  // position
            {0, 0, 0},     // color
            {-1, 0, 0},    // normal
            {0, 1, -1}     // texCoord
        }
    },
    {
        {
            {-L, +L, +L},  // position
            {0, 0, 0},     // color
            {0, 1, 0},     // normal
            {1, 1, VOXEL_TEX_GRASS} // texCoord
        },
        {
            {+L, -L, -L},  // position
            {0, 0, 0},     // color
            {0, -1, 0},    // normal
            {0, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {
            {+L, -L, +L},  // position
            {0, 0, 0},     // color
            {0, 0, 1},     // normal
            {1, 1, -1}     // texCoord
        },
        {
            {-L, +L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, -1},    // normal
            {0, 0, -1}     // texCoord
        },
        {
            {+L, +L, -L},  // position
            {0, 0, 0},     // color
            {1, 0, 0},     // normal
            {0, 0, -1}     // texCoord
        },
        {
            {-L, -L, +L},  // position
            {0, 0, 0},     // color
            {-1, 0, 0},    // normal
            {1, 1, -1}     // texCoord
        }
    },
    {
        {
            {+L, +L, +L},  // position
            {0, 0, 0},     // color
            {0, 1, 0},     // normal
            {0, 1, VOXEL_TEX_GRASS} // texCoord
        },
        {
            {+L, -L, +L},  // position
            {0, 0, 0},     // color
            {0, -1, 0},    // normal
            {0, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {
            {+L, +L, +L},  // position
            {0, 0, 0},     // color
            {0, 0, 1},     // normal
            {1, 0, -1}     // texCoord
        },
        {
            {+L, +L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, -1},    // normal
            {1, 0, -1}     // texCoord
        },
        {
            {+L, +L, +L},  // position
            {0, 0, 0},     // color
            {1, 0, 0},     // normal
            {1, 0, -1}     // texCoord
        },
        {
            {-L, +L, +L},  // position
            {0, 0, 0},     // color
            {-1, 0, 0},    // normal
            {1, 0, -1}     // texCoord
        }
    },
    {
        {
            {+L, +L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, 0},     // normal
            {0, 0, VOXEL_TEX_GRASS} // texCoord
        },
        {
            {-L, -L, +L},  // position
            {0, 0, 0},     // color
            {0, -1, 0},    // normal
            {1, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {
            {-L, +L, +L},  // position
            {0, 0, 0},     // color
            {0, 0, 1},     // normal
            {0, 0, -1}     // texCoord
        },
        {
            {+L, -L, -L},  // position
            {0, 0, 0},     // color
            {0, 1, -1},    // normal
            {1, 1, -1}     // texCoord
        },
        {
            {+L, -L, +L},  // position
            {0, 0, 0},     // color
            {1, 0, 0},     // normal
            {1, 1, -1}     // texCoord
        },
        {
            {-L, +L, -L},  // position
            {0, 0, 0},     // color
            {-1, 0, 0},    // normal
            {0, 0, -1}     // texCoord
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

    GLfloat page = VOXEL_TEX_DIRT;

    GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    GSChunkVoxelData *centerVoxels = [voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER];

    block_lighting_t sunlight;
    [centerVoxels.sunlight interpolateLightAtPoint:chunkLocalPos outLighting:&sunlight];

    // TODO: add torch lighting to the world.
    block_lighting_t torchLight;
    bzero(&torchLight, sizeof(torchLight));

    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        if([voxelData cubeAtPoint:GSIntegerVector3_Add(chunkLocalPos, test[i])]) {
            continue;
        }

        unsigned unpackedSunlight[4];
        unsigned unpackedTorchlight[4];

        if(i == FACE_TOP) {
            page = VOXEL_TEX_SIDE;
        }

        unpackBlockLightingValuesForVertex(sunlight.face[i], unpackedSunlight);
        unpackBlockLightingValuesForVertex(torchLight.face[i], unpackedTorchlight);

        for(size_t j=0; j<4; ++j)
        {
            struct vertex v = meshCube[j][i];

            // translate point within the world
            v.position[0] += pos.v[0];
            v.position[1] += pos.v[1];
            v.position[2] += pos.v[2];

            // select the texture
            v.texCoord[2] = (v.texCoord[2]<0) ? page : v.texCoord[2];

            // set the vertex color (red and alpha channels are unused)
            v.color[1] = (unpackedSunlight[j] / (float)CHUNK_LIGHTING_MAX) * 204 + 51; // sunlight in green channel
            v.color[2] = 255 * unpackedTorchlight[j] / (float)CHUNK_LIGHTING_MAX; // torchlight in blue channel

            [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v] autorelease]];
        }
    }
}

@end
