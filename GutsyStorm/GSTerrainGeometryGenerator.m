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
    int light;
} GSCubeVertex;


static inline vector_float3 vertexPosition(GSCubeVertex a1, GSCubeVertex a2)
{
    return vector_mix(a1.p, a2.p, (vector_float3){0.5, 0.5, 0.5});
}


static inline float clampf(float value, float min, float max)
{
    return MIN(MAX(value, min), max);
}


static vector_uchar4 vertexColor(GSCubeVertex v1, GSCubeVertex v2,
                                 vector_float3 vertexPos,
                                 vector_float3 chunkMinP,
                                 float aoRayContributions[8],
                                 GSVoxel * _Nonnull voxels,
                                 GSIntAABB * _Nonnull voxelBox)
{
    float count = 0;
    float escaped = 0;
    float *pcontribution = aoRayContributions;

    // Cast rays from the vertex to neighboring voxels and count what proportion of the escape.
    // Modify each neighbor's contribution to the occlusion factor by the angle between the ray and the face normal.
    // These contributions are computed once per face.
    for(float dx = -0.5f; dx <= 0.5f; dx += 1.0f)
    {
        for(float dy = -0.5f; dy <= 0.5f; dy += 1.0f)
        {
            for(float dz = -0.5f; dz <= 0.5f; dz += 1.0f)
            {
                float contribution = *pcontribution;
                
                if (contribution > 0) {
                    // Did this ray escape the cell?
                    vector_float3 lightDir = {dx, dy, dz};
                    vector_long3 aoSamplePoint = vector_long(vertexPos - chunkMinP + lightDir);
                    BOOL escape = !voxels[INDEX_BOX(aoSamplePoint, *voxelBox)].opaque;

                    escaped += escape ? contribution : 0;
                    count += contribution;
                }
                
                pcontribution++;
            }
        }
    }
    
    float ambientOcclusion = (float)escaped / count;
    float lightValue = MAX(v1.light, v2.light) / (float)CHUNK_LIGHTING_MAX;
    uint8_t luminance = (uint8_t)clampf(204.0f * (lightValue * ambientOcclusion) + 51.0f, 0.0f, 255.0f);
    return (vector_uchar4){luminance, luminance, luminance, 1};
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
                   GSVoxel * _Nonnull voxels,
                   GSIntAABB * _Nonnull voxelBox,
                   GSCubeVertex a1, GSCubeVertex a2,
                   GSCubeVertex b1, GSCubeVertex b2,
                   GSCubeVertex c1, GSCubeVertex c2)
{
    vector_float3 pa = vertexPosition(a1, a2);
    vector_float3 pb = vertexPosition(b1, b2);
    vector_float3 pc = vertexPosition(c1, c2);
    
    // One normal for the entire face.
    vector_float3 normal = vector_normalize(vector_cross(pb-pa, pc-pa));
    
    // Modify each neighbor's contribution to the ambient occlusion factor by the angle between the ray and the face
    // normal. These contributions are computed once per face and are used on each vertex.
    float aoRayContributions[8];
    float *contribution = &aoRayContributions[0];
    for(float dx = -0.5f; dx <= 0.5f; dx += 1.0f)
    {
        for(float dy = -0.5f; dy <= 0.5f; dy += 1.0f)
        {
            for(float dz = -0.5f; dz <= 0.5f; dz += 1.0f)
            {
                vector_float3 lightDir = {dx, dy, dz};
                *contribution = vector_dot(normal, lightDir) / vector_length(lightDir);
                contribution++;
            }
        }
    }
    
    vector_uchar4 ca = vertexColor(a1, a2, pa, chunkMinP, aoRayContributions, voxels, voxelBox);
    vector_uchar4 cb = vertexColor(b1, b2, pb, chunkMinP, aoRayContributions, voxels, voxelBox);
    vector_uchar4 cc = vertexColor(c1, c2, pc, chunkMinP, aoRayContributions, voxels, voxelBox);
    
    emitVertex(geometry, pa, ca, a1.voxel->tex, normal);
    emitVertex(geometry, pb, cb, b1.voxel->tex, normal);
    emitVertex(geometry, pc, cc, c1.voxel->tex, normal);
}


static void polygonizeTetrahedron(GSTerrainGeometry * _Nonnull geometry,
                                  vector_float3 chunkMinP,
                                  GSVoxel * _Nonnull voxels,
                                  GSIntAABB * _Nonnull voxelBox,
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
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x02:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x04:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x08:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[3]], cube[tetrahedron[1]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x03:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            break;
            
        case 0x05:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]]);
            break;
            
        case 0x09:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]]);
            break;
            
        case 0x06:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[0]], cube[tetrahedron[1]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[0]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]]);
            break;
            
        case 0x0C:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[2]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[1]]);
            break;
            
        case 0x0A:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[2]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[3]], cube[tetrahedron[0]]);
            break;
            
        case 0x07:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[3]], cube[tetrahedron[0]],
                   cube[tetrahedron[3]], cube[tetrahedron[2]],
                   cube[tetrahedron[3]], cube[tetrahedron[1]]);
            break;
            
        case 0x0B:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[2]], cube[tetrahedron[1]],
                   cube[tetrahedron[2]], cube[tetrahedron[3]],
                   cube[tetrahedron[2]], cube[tetrahedron[0]]);
            break;
            
        case 0x0D:
            addTri(geometry, chunkMinP, voxels, voxelBox,
                   cube[tetrahedron[1]], cube[tetrahedron[0]],
                   cube[tetrahedron[1]], cube[tetrahedron[3]],
                   cube[tetrahedron[1]], cube[tetrahedron[2]]);
            break;
            
        case 0x0E:
            addTri(geometry, chunkMinP, voxels, voxelBox,
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
                                         GSIntAABB * _Nonnull lightBox,
                                         vector_float3 cellPos)
{
    vector_long3 chunkLocalPos = vector_long(cellPos - chunkMinP);
    GSCubeVertex vertex = {
        .p = cellPos,
        .voxel = &voxels[INDEX_BOX(chunkLocalPos, voxelBox)],
        .light = light[INDEX_BOX(chunkLocalPos, *lightBox)],
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
            polygonizeTetrahedron(geometry, chunkMinP, voxels, &voxelBox, cube, tetrahedra[i]);
        }
    }
}
