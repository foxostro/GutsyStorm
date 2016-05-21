//
//  GSTerrainGeometryGenerator.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

// Marching Tetrahedra algorithm based on article at <http://paulbourke.net/geometry/polygonise/>.

#import "GSTerrainGeometryGenerator.h"
#import "GSTerrainGeometry.h"
#import "GSChunkVoxelData.h"
#import "GSChunkSunlightData.h"
#import "GSTerrainBuffer.h"
#import "GSVoxelNeighborhood.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


typedef struct
{
    vector_float3 p;
    GSVoxel voxel;
    GSTerrainBufferElement light;
} GSCubeVertex;


static inline void addVertex(GSTerrainGeometry * _Nonnull geometry, GSCubeVertex p1, GSCubeVertex p2)
{
    assert(geometry);
    
    vector_float3 pos = vector_mix(p1.p, p2.p, (vector_float3){0.5, 0.5, 0.5});

    vector_float4 color = {0, 0, 0, 1};
    color.y = 204.0f * ((p1.light + p2.light) / (float)CHUNK_LIGHTING_MAX) + 51.0f; // sunlight in the green channel

    GSTerrainVertex vertex = {
        .position = {pos.x, pos.y, pos.z},
        .color = {color.x, color.y, color.z, color.w},
        .texCoord = {0, 0, 0}, // AFOX_TODO: texture coordinates
    };
    GSTerrainGeometryAddVertex(geometry, &vertex);
}


static void polygonizeTetrahedron(GSTerrainGeometry * _Nonnull geometry,
                                  GSCubeVertex cube[8],
                                  const size_t tetrahedron[4])
{
    assert(geometry);
    
    unsigned index = 0;
    
    for(int i = 0; i < 4; ++i)
    {
        if (cube[tetrahedron[i]].voxel.type != VOXEL_TYPE_EMPTY)
        {
            index |= (1 << i);
        }
    }
    
    switch(index)
    {
        case 0x00:
        case 0x0F:
            break;
            
        case 0x01:
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x02:
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x04:
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x08:
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x03:
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x05:
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[0]]);
            
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[3]]);
            break;
            
        case 0x09:
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x06:
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[2]]);
            break;
            
        case 0x0C:
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x0A:
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x07:
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[3]], cube[tetrahedron[1]]);
            break;
            
        case 0x0B:
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[2]], cube[tetrahedron[0]]);
            break;
            
        case 0x0D:
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[0]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[3]]);
            addVertex(geometry, cube[tetrahedron[1]], cube[tetrahedron[2]]);
            break;
            
        case 0x0E:
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[1]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[2]]);
            addVertex(geometry, cube[tetrahedron[0]], cube[tetrahedron[3]]);
            break;
    }
}


static inline GSCubeVertex getCubeVertex(vector_float3 chunkMinP,
                                         GSChunkVoxelData * _Nonnull voxels,
                                         GSChunkSunlightData * _Nonnull sunlight,
                                         vector_float3 cellPos)
{
    assert(voxels);
    assert(sunlight);

    vector_long3 chunkLocalPos = vector_long(cellPos - chunkMinP);

    GSCubeVertex vertex = {
        .p = cellPos,
        .voxel = [voxels voxelAtLocalPosition:chunkLocalPos],
        .light = [sunlight.sunlight valueAtPosition:chunkLocalPos],
    };

    return vertex;
}


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSChunkSunlightData * _Nonnull sunlight,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex)
{
    assert(geometry);
    assert(sunlight);
    
    static const float L = 0.5f;
    GSChunkVoxelData *voxels = [sunlight.neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER];

    // Get the sub-chunk bounding box and offset to align with the grid cells used for the tetrahedra.
    GSIntAABB ibounds = GSTerrainGeometrySubchunkBoxInt(chunkMinP, subchunkIndex);
    GSFloatAABB bounds = {
        .mins = vector_float(ibounds.mins) + vector_make(L, L, L),
        .maxs = vector_float(ibounds.maxs) + vector_make(L, L, L)
    };

    vector_float3 pos;
    FOR_BOX(pos, bounds)
    {
        GSCubeVertex cube[8] = {
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(-L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(+L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(+L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(-L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(-L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(+L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(+L, +L, -L)),
            getCubeVertex(chunkMinP, voxels, sunlight, pos + vector_make(-L, +L, -L))
        };
        
        static const size_t tetrahedra[6][4] = {
            { 0, 7, 3, 2 },
            { 0, 7, 2, 6 },
            { 0, 4, 7, 6 },
            { 0, 1, 6, 2 },
            { 0, 4, 6, 1 },
            { 5, 1, 6, 4 }
        };
        
        for(int i = 0; i < 6; ++i)
        {
            polygonizeTetrahedron(geometry, cube, tetrahedra[i]);
        }
    }
}
