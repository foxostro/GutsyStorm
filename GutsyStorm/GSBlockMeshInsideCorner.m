//
//  GSBlockMeshInsideCorner.m
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
#import "GSBlockMeshInsideCorner.h"

const static GLfloat L = 0.5f; // half the length of a block along one side

const static struct vertex mesh[] =
{
    // Top (ramp surface)
    {
        {-L, +L, -L},           // position
        {0, 0, 0},              // color
        {0, 1, 0},              // normal
        {1, 1, VOXEL_TEX_GRASS} // texCoord
    },
    {
        {-L, +L, +L},           // position
        {0, 0, 0},              // color
        {0, 1, 0},              // normal
        {1, 0, VOXEL_TEX_GRASS} // texCoord
	},
    {
        {+L, +L, +L},           // position
        {0, 0, 0},              // color
        {0, 1, 0},              // normal
        {0, 0, VOXEL_TEX_GRASS} // texCoord
	},
    {
        {+L, -L, -L},           // position
        {0, 0, 0},              // color
        {0, 0, -1},             // normal
        {0, 1, VOXEL_TEX_GRASS} // texCoord
	},

    // Bottom
    {
        {-L, -L, -L},          // position
        {0, 0, 0},             // color
        {0, -1, 0},            // normal
        {1, 0, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, -L},          // position
        {0, 0, 0},             // color
        {0, -1, 0},            // normal
        {0, 0, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, +L},          // position
        {0, 0, 0},             // color
        {0, -1, 0},            // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, -L, +L},          // position
        {0, 0, 0},             // color
        {0, -1, 0},            // normal
        {1, 1, VOXEL_TEX_DIRT} // texCoord
	},

    // Side A (a triangle)
    {
        {+L, +L, +L},          // position
        {0, 0, 0},             // color
        {1, 0, 0},             // normal
        {1, 0, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, +L},          // position
        {0, 0, 0},             // color
        {1, 0, 0},             // normal
        {1, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, -L},          // position
        {0, 0, 0},             // color
        {1, 0, 0},             // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, -L},          // position
        {0, 0, 0},             // color
        {1, 0, 0},             // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},

    // Side B (a triangle)
    {
        {+L, -L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, -L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, +L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 0, VOXEL_TEX_DIRT} // texCoord
	},

    // Side C (a full square)
    {
        {-L, +L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 0, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, -L, -L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, -L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, +L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 0, VOXEL_TEX_DIRT} // texCoord
	},

    // Side D (a full square)
    {
        {-L, +L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 0, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {-L, -L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {0, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, -L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 1, VOXEL_TEX_DIRT} // texCoord
	},
    {
        {+L, +L, +L},          // position
        {0, 0, 0},             // color
        {-1, 0, 0},            // normal
        {1, 0, VOXEL_TEX_DIRT} // texCoord
	},
};

@implementation GSBlockMeshInsideCorner

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
    voxel_t voxel = [centerVoxels voxelAtLocalPosition:chunkLocalPos];
    GLKQuaternion quat = quaternionForDirection(voxel.dir);

    const size_t numVerts = sizeof(mesh) / sizeof(mesh[0]);
    assert(numVerts % 4 == 0);

    for(size_t i = 0; i < numVerts; ++i)
    {
        struct vertex v = mesh[i];

        // rotate the mesh
        GLKVector3 vertexPos = GLKVector3Make(v.position[0], v.position[1], v.position[2]);
        vertexPos = GLKQuaternionRotateVector3(quat, vertexPos);
        v.position[0] = vertexPos.v[0] + pos.v[0];
        v.position[1] = vertexPos.v[1] + pos.v[1];
        v.position[2] = vertexPos.v[2] + pos.v[2];

        // rotate the normal too
        GLKVector3 normal = GLKVector3Make(v.normal[0], v.normal[1], v.normal[2]);
        normal = GLKQuaternionRotateVector3(quat, normal);
        v.normal[0] = normal.v[0];
        v.normal[1] = normal.v[1];
        v.normal[2] = normal.v[2];

        [vertexList addObject:[[[GSVertex alloc] initWithVertex:&v] autorelease]];
    }
}

@end
