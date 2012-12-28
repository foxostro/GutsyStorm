//
//  GSBlockMeshRamp.m
//  GutsyStorm
//
//  Created by Andrew Fox on 12/27/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSVertex.h"
#import "Voxel.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshRamp.h"

const static GLfloat L = 0.5f; // half the length of a block along one side

struct ramp_vertex
{
    struct vertex v;

    /* These arrays let us rotate the block_lighting_t values when we rotate the ramp mesh.
     * Each vertex in the ramp is associated with a face and specific vertex in the block_lighting_t.
     * Index into the array using the values in voxel_dir_t.
     */
    face_t face[4];
    size_t idx[4];
};

const static struct ramp_vertex meshRamp[] =
{
    // Top
    {
        {
            {-L, -L, -L},           // position
            {255, 255, 255},        // color
            {0, 0.707, 0.707},      // normal
            {1, 1, VOXEL_TEX_GRASS} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {0, 0, 0, 0}
    },
    {
	    {
            {-L, +L, +L},           // position
            {255, 255, 255},        // color
            {0, 0.707, 0.707},      // normal
            {1, 0, VOXEL_TEX_GRASS} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {1, 0, 0, 0}
	},
    {
	    {
            {+L, +L, +L},           // position
            {255, 255, 255},        // color
            {0, 0.707, 0.707},      // normal
            {0, 0, VOXEL_TEX_GRASS} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {2, 0, 0, 0}
	},
    {
	    {
            {+L, -L, -L},           // position
            {255, 255, 255},        // color
            {0, 0.707, 0.707},      // normal
            {0, 1, VOXEL_TEX_GRASS} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {3, 0, 0, 0}
	},

    // Bottom
    {
	    {
            {-L, -L, -L},          // position
            {255, 255, 255},       // color
            {0, -1, 0},            // normal
            {1, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM},
        {0, 0, 0, 0}
	},
    {
	    {
            {+L, -L, -L},          // position
            {255, 255, 255},       // color
            {0, -1, 0},            // normal
            {0, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM},
        {1, 0, 0, 0}
	},
    {
	    {
            {+L, -L, +L},          // position
            {255, 255, 255},       // color
            {0, -1, 0},            // normal
            {0, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM},
        {2, 0, 0, 0}
	},
    {
	    {
            {-L, -L, +L},          // position
            {255, 255, 255},       // color
            {0, -1, 0},            // normal
            {1, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM, FACE_BOTTOM},
        {3, 0, 0, 0}
	},

    // Back
    {
	    {
            {-L, -L, +L},          // position
            {255, 255, 255},       // color
            {0, 0, +1},            // normal
            {0, 1, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_BACK, FACE_BACK, FACE_BACK, FACE_BACK},
        {0, 0, 0, 0}
	},
    {
	    {
            {+L, -L, +L},          // position
            {255, 255, 255},       // color
            {0, 0, +1},            // normal
            {1, 1, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {1, 0, 0, 0}
	},
    {
	    {
            {+L, +L, +L},          // position
            {255, 255, 255},       // color
            {0, 0, +1},            // normal
            {1, 0, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {2, 0, 0, 0}
	},
    {
	    {
            {-L, +L, +L},          // position
            {255, 255, 255},       // color
            {0, 0, +1},            // normal
            {0, 0, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_TOP, FACE_TOP, FACE_TOP, FACE_TOP},
        {3, 0, 0, 0}
	},

    // Side A
    {
	    {
            {+L, +L, +L},          // position
            {255, 255, 255},       // color
            {1, 0, 0},             // normal
            {0, 1, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_RIGHT, FACE_RIGHT, FACE_RIGHT, FACE_RIGHT},
        {0, 0, 0, 0}
	},
    {
	    {
            {+L, -L, +L},          // position
            {255, 255, 255},       // color
            {1, 0, 0},             // normal
            {1, 1, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_RIGHT, FACE_RIGHT, FACE_RIGHT, FACE_RIGHT},
        {1, 0, 0, 0}
	},
    {
	    {
            {+L, -L, -L},          // position
            {255, 255, 255},       // color
            {1, 0, 0},             // normal
            {1, 0, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_RIGHT, FACE_RIGHT, FACE_RIGHT, FACE_RIGHT},
        {2, 0, 0, 0}
	},
    {
	    {
            {+L, -L, -L},          // position
            {255, 255, 255},       // color
            {1, 0, 0},             // normal
            {1, 0, VOXEL_TEX_SIDE} // texCoord
        },
        {FACE_RIGHT, FACE_RIGHT, FACE_RIGHT, FACE_RIGHT},
        {3, 0, 0, 0}
	},

    // Side B
    {
	    {
            {-L, -L, -L},          // position
            {255, 255, 255},       // color
            {-1, 0, 0},            // normal
            {0, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_LEFT, FACE_LEFT, FACE_LEFT, FACE_LEFT},
        {0, 0, 0, 0}
	},
    {
	    {
            {-L, -L, -L},          // position
            {255, 255, 255},       // color
            {-1, 0, 0},            // normal
            {0, 0, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_LEFT, FACE_LEFT, FACE_LEFT, FACE_LEFT},
        {1, 0, 0, 0}
	},
    {
	    {
            {-L, -L, +L},          // position
            {255, 255, 255},       // color
            {-1, 0, 0},            // normal
            {0, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_LEFT, FACE_LEFT, FACE_LEFT, FACE_LEFT},
        {2, 0, 0, 0}
	},
    {
	    {
            {-L, +L, +L},          // position
            {255, 255, 255},       // color
            {-1, 0, 0},            // normal
            {1, 1, VOXEL_TEX_DIRT} // texCoord
        },
        {FACE_LEFT, FACE_LEFT, FACE_LEFT, FACE_LEFT},
        {3, 0, 0, 0}
	},
};

@implementation GSBlockMeshRamp

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
    GSChunkVoxelData *centerVoxels = [voxelData neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    voxel_dir_t dir = [centerVoxels voxelAtLocalPosition:chunkLocalPos].dir;
    GLKQuaternion quat = GLKQuaternionMakeWithAngleAndAxis((int)dir * M_PI_2, 0, 1, 0);

    //block_lighting_t sunlight;
    //[centerVoxels.sunlight interpolateLightAtPoint:chunkLocalPos outLighting:&sunlight];

    // TODO: add torch lighting to the world.
    //block_lighting_t torchLight;
    //bzero(&torchLight, sizeof(torchLight));

    const size_t numVerts = sizeof(meshRamp) / sizeof(meshRamp[0]);
    assert(numVerts % 4 == 0);
    
    for(size_t i = 0; i < numVerts; ++i)
    {
        struct ramp_vertex v = meshRamp[i];

        // rotate the ramp and translate within the world
        GLKVector3 vertexPos = GLKVector3Make(v.v.position[0], v.v.position[1], v.v.position[2]);
        vertexPos = GLKQuaternionRotateVector3(quat, vertexPos);
        v.v.position[0] = vertexPos.v[0] + pos.v[0];
        v.v.position[1] = vertexPos.v[1] + pos.v[1];
        v.v.position[2] = vertexPos.v[2] + pos.v[2];

        // set the vertex color (red and alpha channels are unused)
        //unsigned unpackedSunlight[4];
        //unsigned unpackedTorchlight[4];
        //face_t face = v.face[dir];
        //size_t idx = v.idx[dir];

        //unpackBlockLightingValuesForVertex(sunlight.face[face], unpackedSunlight);
        //unpackBlockLightingValuesForVertex(torchLight.face[face], unpackedTorchlight);
        
        //v.v.color[1] = (unpackedSunlight[idx] / (float)CHUNK_LIGHTING_MAX) * 204 + 51; // sunlight in green channel
        //v.v.color[2] = 255 * unpackedTorchlight[idx] / (float)CHUNK_LIGHTING_MAX; // torchlight in blue channel
        v.v.color[1] = 255;
        v.v.color[2] = 255;

        [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v.v] autorelease]];
    }
}

@end
