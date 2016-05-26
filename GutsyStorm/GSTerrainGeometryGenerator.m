//
//  GSTerrainGeometryGenerator.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGeometryGenerator.h"
#import "GSTerrainGeometry.h"
#import "GSChunkVoxelData.h"
#import "GSChunkSunlightData.h"
#import "GSTerrainBuffer.h"
#import "GSVoxelNeighborhood.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


typedef struct {
    vector_float3 p;
    const GSVoxel *voxel;
    int light;
} GSCubeVertex;


typedef struct {
    size_t v1, v2;
} GSPair;


static const int NUM_CUBE_EDGES = 12;
static const int NUM_CUBE_VERTS = 8;

static const GSVoxel gEmpty = {
    .outside = 1,
    .torch = 0,
    .opaque = 0,
    .type = VOXEL_TYPE_EMPTY,
    .texTop = 0,
    .texSide = 0
};


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
                                 vector_float3 normal,
                                 GSVoxel * _Nonnull voxels,
                                 GSIntAABB * _Nonnull voxelBox)
{
    float count = 0;
    float escaped = 0;

    // Cast rays from the vertex to neighboring cells and count what proportion of the rays escape.
    // Modify each neighbor's contribution to the occlusion factor by the angle between the ray and the face normal.
    // These contributions are computed once per face.
    for(float dx = -1; dx <= 1; dx += 1.0f)
    {
        for(float dy = -1; dy <= 1; dy += 1.0f)
        {
            for(float dz = -1; dz <= 1; dz += 1.0f)
            {
                vector_float3 lightDir = {dx, dy, dz};

                float contribution = vector_dot(normal, lightDir) / vector_length(lightDir);

                if (contribution > 0) {
                    // Did this ray escape the cell?
                    vector_long3 aoSamplePoint = vector_long(vertexPos - chunkMinP + lightDir);
                    BOOL escape = !voxels[INDEX_BOX(aoSamplePoint, *voxelBox)].opaque;

                    escaped += escape ? contribution : 0;
                    count += contribution;
                }
            }
        }
    }
    
    float ambientOcclusion = (float)escaped / count;
    float lightValue = MAX(v1.light, v2.light) / (float)CHUNK_LIGHTING_MAX;
    uint8_t luminance = (uint8_t)clampf(204.0f * (lightValue * ambientOcclusion) + 51.0f, 0.0f, 255.0f);
    return (vector_uchar4){luminance, luminance, luminance, 1};
}


static inline void emitVertex(GSTerrainGeometry * _Nonnull geometry, vector_float3 p,
                              vector_uchar4 c, int texTop, int texSide, vector_float3 n)
{
    vector_float3 texCoord = vector_make(p.x, p.z, 0);
    
    if (n.y == 0) {
        if (n.x != 0) {
            texCoord = vector_make(p.z, p.y, texSide);
        } else {
            texCoord = vector_make(p.x, p.y, texSide);
        }
    } else if (n.y > 0) {
        texCoord = vector_make(p.x, p.z, texTop);
    } else {
        texCoord = vector_make(p.x, p.z, texSide);
    }

    GSTerrainVertex v = {
        .position = {p.x, p.y, p.z},
        .color = {c.x, c.y, c.z, c.w},
        .texCoord = {texCoord.x, texCoord.y, texCoord.z}
    };

    GSTerrainGeometryAddVertex(geometry, &v);
}


static void addTri(GSTerrainGeometry * _Nonnull geometry,
                   vector_float3 chunkMinP,
                   GSVoxel * _Nonnull voxels,
                   GSIntAABB * _Nonnull voxelBox,
                   GSCubeVertex v1[3],
                   GSCubeVertex v2[3],
                   int texTop,
                   int texSide)
{
    vector_float3 p[3];
    vector_uchar4 c[3];
    GSVoxel faceVoxel[3];

    for(int i = 0; i < 3; ++i)
    {
        p[i] = vertexPosition(v1[i], v2[i]);
    }
    
    // One normal for the entire face.
    vector_float3 normal = vector_normalize(vector_cross(p[1]-p[0], p[2]-p[0]));
    
    for(int i = 0; i < 3; ++i)
    {
        c[i] = vertexColor(v1[i], v2[i], p[i], chunkMinP, normal, voxels, voxelBox);
    }

    for(int i = 0; i < 3; ++i)
    {
        faceVoxel[i] = (v1[i].voxel->type != VOXEL_TYPE_GROUND) ? *v2[i].voxel : *v1[i].voxel;
    }

    for(int i = 0; i < 3; ++i)
    {
        emitVertex(geometry, p[i], c[i], texTop, texSide, normal);
    }
}


static void polygonizeGridCell(GSTerrainGeometry * _Nonnull geometry,
                               GSCubeVertex cube[NUM_CUBE_VERTS],
                               vector_float3 chunkMinP,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB * _Nonnull voxelBox)
{
    // Based on Paul Bourke's Marching Cubes algorithm at <http://paulbourke.net/geometry/polygonise/>.
    // The edge and tri tables come directly from the sample code in the article.

    assert(geometry);
    
    static const unsigned edgeTable[256] = {
#include "edgetable.def"
    };

    static const int triTable[256][16] = {
#include "tritable.def"
    };
    
    // Build an index to look into the tables. Examine each of the eight neighboring cells and set a bit in the index
    // to '0' or '1' depending on whether the neighboring voxel is empty or not-empty.
    unsigned index = 0;
    for(size_t i = 0; i < NUM_CUBE_VERTS; ++i)
    {
        if (cube[i].voxel->type == VOXEL_TYPE_GROUND) {
            index |= (1 << i);
        }
    }
    
    // If all neighbors are empty then there's nothing to do. Bail out early.
    if (edgeTable[index] == 0) {
        return;
    }
    
    // For each intersection between the surface and the cube, record the indices of the two cube vertices on either
    // side of the intersection. We interpolate the vertices later, when emitting triangles.
    GSPair vertexList[NUM_CUBE_EDGES] = {0};
    {
        static const size_t intersect1[NUM_CUBE_EDGES] = {0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3};
        static const size_t intersect2[NUM_CUBE_EDGES] = {1, 2, 3, 0, 5, 6, 7, 4, 4, 5, 6, 7};
        
        for(size_t i = 0; i < NUM_CUBE_EDGES; ++i)
        {
            if (edgeTable[index] & (1 << i)) {
                vertexList[i] = (GSPair){ intersect1[i], intersect2[i] };
            }
        }
    }

    // Select the texture for the face.
    // TODO: We should examine the top face of the cube of neighbor voxels in order to determine the texture to use.
    // Right now, we search the cube for any adjacent voxel that isn't empty (there's at least one) and use whatever
    // textures it has. Instead, we should split the cube into faces and examine the voxel neighbors of each face to
    // determine which texture to use.
    int texTop, texSide;
    for(int i = 0; i < NUM_CUBE_VERTS; ++i)
    {
        if (cube[i].voxel->type == VOXEL_TYPE_GROUND) {
            texTop = cube[i].voxel->texTop;
            texSide = cube[i].voxel->texSide;
        }
    }

    for(size_t i = 0; triTable[index][i] != -1; i += 3)
    {
        GSPair pairs[3] = {
            vertexList[triTable[index][i+2]],
            vertexList[triTable[index][i+1]],
            vertexList[triTable[index][i+0]]
        };
        
        GSCubeVertex v1[3], v2[3];

        for(int j = 0; j < 3; ++j)
        {
            v1[j] = cube[pairs[j].v1];
            v2[j] = cube[pairs[j].v2];
        }

        addTri(geometry, chunkMinP, voxels, voxelBox, v1, v2, texTop, texSide);
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
    if (chunkLocalPos.y >= CHUNK_SIZE_Y) {
        return (GSCubeVertex){
            .p = cellPos,
            .voxel = &gEmpty,
            .light = CHUNK_LIGHTING_MAX
        };
    } else {
        return (GSCubeVertex){
            .p = cellPos,
            .voxel = &voxels[INDEX_BOX(chunkLocalPos, voxelBox)],
            .light = light[INDEX_BOX(chunkLocalPos, *lightBox)],
        };
    }
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

    // Get the sub-chunk bounding box and offset to align with the grid cells used.
    GSIntAABB ibounds = GSTerrainGeometrySubchunkBoxInt(chunkMinP, subchunkIndex);
    GSFloatAABB bounds = {
        .mins = vector_float(ibounds.mins) + vector_make(L, L, L),
        .maxs = vector_float(ibounds.maxs) + vector_make(L, L, L)
    };

    vector_float3 pos;
    FOR_BOX(pos, bounds)
    {
        GSCubeVertex cube[NUM_CUBE_VERTS] = {
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, -L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, -L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, +L, +L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(+L, +L, -L)),
            getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos + vector_make(-L, +L, -L))
        };

        polygonizeGridCell(geometry, cube, chunkMinP, voxels, &voxelBox);
    }
}
