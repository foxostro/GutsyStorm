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
    GSVoxel *voxel;
} GSCubeVertex;


static inline vector_float3 vertexPosition(GSCubeVertex a1, GSCubeVertex a2)
{
    return vector_mix(a1.p, a2.p, (vector_float3){0.5, 0.5, 0.5});
}


static inline float clampf(float value, float min, float max)
{
    return MIN(MAX(value, min), max);
}


static vector_uchar4 vertexColor(vector_float3 vertexPos, vector_float3 chunkMinP, vector_float3 normal,
                                 GSTerrainBufferElement * _Nonnull light, GSIntAABB * _Nonnull lightBox)
{
    float accumLight = 0;
    
    // Sample the light at the sunlight cells adjacent to this vertex add their contributions to the vertex's overall
    // lighting. Use the n.l dot product to scale contributions according to the angle at which they hit the face.
    for(float dx = -0.5f; dx <= 0.5f; dx += 1.0f)
    {
        for(float dy = -0.5f; dy <= 0.5f; dy += 1.0f)
        {
            for(float dz = -0.5f; dz <= 0.5f; dz += 1.0f)
            {
                vector_float3 lightDir = {dx, dy, dz};
                vector_long3 aoSamplePoint = vector_long(vertexPos - chunkMinP + lightDir);
                float aoSample = light[INDEX_BOX(aoSamplePoint, *lightBox)];
                float scale = clampf(vector_dot(normal, vector_normalize(lightDir)), 0, 1);
                accumLight += scale * aoSample;
            }
        }
    }
    
    accumLight = clampf(accumLight, 0, CHUNK_LIGHTING_MAX);
    
    // Pack the overall light value into the green channel of the color. The shader expects this.
    uint8_t luminence = (uint8_t)(204.0f * (accumLight / CHUNK_LIGHTING_MAX) + 51.0f);
    return (vector_uchar4){0, luminence, 0, 1};
}


static inline void emitVertex(GSTerrainGeometry * _Nonnull geometry, vector_float3 p,
                              vector_uchar4 c, int tex, vector_float3 n)
{
    vector_float3 texCoord = vector_make(p.x, p.z, tex);
    
    if (n.y == 0) {
        if (n.x != 0) {
            texCoord = vector_make(p.z, p.y, VOXEL_TEX_DIRT);
        } else {
            texCoord = vector_make(p.x, p.y, VOXEL_TEX_DIRT);
        }
    } else if (n.y > 0) {
        texCoord = vector_make(p.x, p.z, tex);
    } else {
        texCoord = vector_make(p.x, p.z, VOXEL_TEX_DIRT);
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
                   vector_float3 chunkMinP,
                   GSTerrainBufferElement * _Nonnull light,
                   GSIntAABB * _Nonnull lightBox,
                   GSCubeVertex a1, GSCubeVertex a2,
                   GSCubeVertex b1, GSCubeVertex b2,
                   GSCubeVertex c1, GSCubeVertex c2)
{
    vector_float3 pa = vertexPosition(a1, a2);
    vector_float3 pb = vertexPosition(b1, b2);
    vector_float3 pc = vertexPosition(c1, c2);
    
    // One normal for the entire face.
    vector_float3 normal = vector_normalize(vector_cross(pb-pa, pc-pa));
    
    vector_uchar4 ca = vertexColor(pa, chunkMinP, normal, light, lightBox);
    vector_uchar4 cb = vertexColor(pb, chunkMinP, normal, light, lightBox);
    vector_uchar4 cc = vertexColor(pc, chunkMinP, normal, light, lightBox);
    
    emitVertex(geometry, pa, ca, a1.voxel->tex, normal);
    emitVertex(geometry, pb, cb, b1.voxel->tex, normal);
    emitVertex(geometry, pc, cc, c1.voxel->tex, normal);
}


static void polygonizeTetrahedron(GSTerrainGeometry * _Nonnull geometry,
                                  vector_float3 chunkMinP,
                                  GSTerrainBufferElement * _Nonnull light,
                                  GSIntAABB * _Nonnull lightBox,
                                  GSCubeVertex cube[8],
                                  const size_t tetrahedron[4])
{
    assert(geometry);
    
    unsigned index = 0;
    
    for(int i = 0; i < 4; ++i)
    {
        if (cube[tetrahedron[i]].voxel->type != VOXEL_TYPE_EMPTY)
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
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x02:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x04:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x08:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[3]], cube[tetrahedron[1]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x03:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x05:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]]);
            break;
            
        case 0x09:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x06:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]]);
            break;
            
        case 0x0C:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x0A:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x07:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[1]]);
            break;
            
        case 0x0B:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]]);
            break;
            
        case 0x0D:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            break;
            
        case 0x0E:
            addTri(geometry, chunkMinP, light, lightBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[0]], cube[tetrahedron[3]]);
            break;
    }
}


static inline GSCubeVertex getCubeVertex(vector_float3 chunkMinP,
                                         GSVoxel * _Nonnull voxels,
                                         GSIntAABB voxelBox,
                                         vector_float3 cellPos)
{
    vector_long3 chunkLocalPos = vector_long(cellPos - chunkMinP);
    GSCubeVertex vertex = {
        .p = cellPos,
        .voxel = &voxels[INDEX_BOX(chunkLocalPos, voxelBox)]
    };
    return vertex;
}


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               GSTerrainBufferElement * _Nonnull light,
                               GSIntAABB * _Nonnull lightBox,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex)
{
    assert(geometry);
    assert(voxels);
    assert(light);
    assert(lightBox);
    
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
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(-L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(+L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(+L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(-L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(-L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(+L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(+L, +L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, pos + vector_make(-L, +L, -L))
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
            polygonizeTetrahedron(geometry, chunkMinP, light, lightBox, cube, tetrahedra[i]);
        }
    }
}
