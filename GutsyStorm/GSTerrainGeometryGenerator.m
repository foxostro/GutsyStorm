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


static inline vector_float3 vertexPosition(GSCubeVertex a1, GSCubeVertex a2)
{
    return vector_mix(a1.p, a2.p, (vector_float3){0.5, 0.5, 0.5});
}


static inline vector_float4 vertexColor(GSCubeVertex a1, GSCubeVertex a2)
{
    vector_float4 color = {0, 0, 0, 1};
    color.y = 204.0f * ((a1.light + a2.light) / (float)CHUNK_LIGHTING_MAX) + 51.0f; // sunlight in the green channel
    return color;
}


static inline void emitVertex(GSTerrainGeometry * _Nonnull geometry, vector_float3 p,
                              vector_float4 c, int tex, vector_float3 n)
{
    static const vector_float3 globalOffset = {-0.5, 0.0, -0.5};
    p = p + globalOffset;
    
    vector_float3 texCoord = vector_make(p.x, p.z, tex);
    
    if (n.y == 0) {
        if (n.x != 0) {
            texCoord = vector_make(p.z, p.y, 1);
        } else {
            texCoord = vector_make(p.x, p.y, 1);
        }
    } else if (n.y > 0) {
        texCoord = vector_make(p.x, p.z, tex);
    } else {
        texCoord = vector_make(p.x, p.z, 1);
    }

    GSTerrainVertex v = {
        .position = {p.x, p.y, p.z},
        .color = {c.x, c.y, c.z, c.w},
        .texCoord = {texCoord.x, texCoord.y, texCoord.z},
        .normal = {n.x, n.y, n.z}
    };

    GSTerrainGeometryAddVertex(geometry, &v);
}


static void addTri(GSTerrainGeometry * _Nonnull geometry,
                   GSCubeVertex a1, GSCubeVertex a2,
                   GSCubeVertex b1, GSCubeVertex b2,
                   GSCubeVertex c1, GSCubeVertex c2)
{
    vector_float3 pa = vertexPosition(a1, a2);
    vector_float3 pb = vertexPosition(b1, b2);
    vector_float3 pc = vertexPosition(c1, c2);
    
    // One normal for the entire face.
    vector_float3 normal = vector_cross(pb-pa, pc-pa);
    
    vector_float4 ca = vertexColor(a1, a2);
    vector_float4 cb = vertexColor(b1, b2);
    vector_float4 cc = vertexColor(c1, c2);
    
    emitVertex(geometry, pa, ca, a1.voxel.tex, normal);
    emitVertex(geometry, pb, cb, b1.voxel.tex, normal);
    emitVertex(geometry, pc, cc, c1.voxel.tex, normal);
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
            addTri(geometry,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x02:
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x04:
            addTri(geometry,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x08:
            addTri(geometry,
                   cube[tetrahedron[3]], cube[tetrahedron[1]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x03:
            addTri(geometry,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x05:
            addTri(geometry,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]]);
            
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]]);
            break;
            
        case 0x09:
            addTri(geometry,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x06:
            addTri(geometry,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]]);
            break;
            
        case 0x0C:
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            
            addTri(geometry,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x0A:
            addTri(geometry,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x07:
            addTri(geometry,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[1]]);
            break;
            
        case 0x0B:
            addTri(geometry,
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]]);
            break;
            
        case 0x0D:
            addTri(geometry,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            break;
            
        case 0x0E:
            addTri(geometry,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[0]], cube[tetrahedron[3]]);
            break;
    }
}


static inline GSCubeVertex getCubeVertex(vector_float3 chunkMinP,
                                         GSVoxel * _Nonnull voxels,
                                         GSIntAABB voxelBox,
                                         GSTerrainBufferElement * _Nonnull light,
                                         GSIntAABB lightBox,
                                         vector_float3 cellPos)
{
    assert(voxels);
    assert(light);

    vector_long3 chunkLocalPos = vector_long(cellPos - chunkMinP);

    GSCubeVertex vertex = {
        .p = cellPos,
        .voxel = voxels[INDEX_BOX(chunkLocalPos, voxelBox)],
        .light = light[INDEX_BOX(chunkLocalPos, lightBox)],
    };

    return vertex;
}


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               GSTerrainBufferElement * _Nonnull light,
                               GSIntAABB lightBox,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex)
{
    assert(geometry);
    assert(voxels);
    assert(light);
    
    static const float L = 0.5f;

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
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, +L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, +L, -L))
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
