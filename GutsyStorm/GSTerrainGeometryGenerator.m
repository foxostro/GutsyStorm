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
    // Vertex position is relative to the position of the cell.
    // The two are separated so as to reduce numerical inaccuracy.
    vector_float3 cellRelativeVertexPos;

    vector_float3 worldPos;
    const GSVoxel *voxel;
    int light;
} GSCubeVertex;


typedef struct {
    size_t v1, v2;
} GSPair;


typedef enum {
    TOP,
    BOTTOM,
    NORTH,
    EAST,
    SOUTH,
    WEST,
    NUM_CUBE_FACES
} GSCubeFace;


static const int NUM_CUBE_EDGES = 12;
static const int NUM_CUBE_VERTS = 8;
static const float L = 0.5f;

static const GSVoxel gEmpty = {
    .outside = 1,
    .torch = 0,
    .opaque = 0,
    .type = VOXEL_TYPE_EMPTY,
    .texTop = 0,
    .texSide = 0
};


static inline float clampf(float value, float min, float max)
{
    return MIN(MAX(value, min), max);
}


static vector_uchar4 vertexColor(GSCubeVertex v1, GSCubeVertex v2,
                                 vector_float3 worldPos,
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
                    vector_long3 aoSamplePoint = vector_long(worldPos - chunkMinP + lightDir);
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


static inline void emitVertex(GSTerrainGeometry * _Nonnull geometry,
                              vector_float3 worldPos, vector_float3 cellRelativeVertexPos,
                              vector_uchar4 c, int tex, vector_float3 n)
{
    vector_float3 texCoord = vector_make(cellRelativeVertexPos.x, cellRelativeVertexPos.z, 0);
    
    if (n.y == 0) {
        if (n.x != 0) {
            texCoord = vector_make(cellRelativeVertexPos.z, cellRelativeVertexPos.y, 0);
        } else {
            texCoord = vector_make(cellRelativeVertexPos.x, cellRelativeVertexPos.y, 0);
        }
    } else if (n.y > 0) {
        texCoord = vector_make(cellRelativeVertexPos.x, cellRelativeVertexPos.z, 0);
    } else {
        texCoord = vector_make(cellRelativeVertexPos.x, cellRelativeVertexPos.z, 0);
    }

    GSTerrainVertex v = {
        .position = {worldPos.x, worldPos.y, worldPos.z},
        .color = {c.x, c.y, c.z, c.w},
        .texCoord = {texCoord.x, texCoord.y, tex}
    };

    GSTerrainGeometryAddVertex(geometry, &v);
}


static inline GSCubeFace determineDirectionFromFaceNormal(vector_float3 normal)
{
    GSCubeFace dir;
    
    if (normal.y > 0) {
        dir = TOP;
    } else if (normal.y < 0) {
        dir = BOTTOM;
    } else {
        if (normal.z > 0) {
            dir = NORTH;
        } else if (normal.z < 0) {
            dir = SOUTH;
        } else if(normal.x > 0) {
            dir = EAST;
        } else {
            dir = WEST;
        }
    }
    
    return dir;
}


static void addTri(GSTerrainGeometry * _Nonnull geometry,
                   vector_float3 chunkMinP,
                   GSVoxel * _Nonnull voxels,
                   GSIntAABB * _Nonnull voxelBox,
                   GSCubeVertex v1[3],
                   GSCubeVertex v2[3],
                   int texForFace[NUM_CUBE_FACES])
{
    vector_float3 worldPos[3];
    vector_float3 cellRelativeVertexPos[3];
    vector_uchar4 c[3];
    GSVoxel faceVoxel[3];

    for(int i = 0; i < 3; ++i)
    {
        worldPos[i] = vector_mix(v1[i].worldPos, v2[i].worldPos, (vector_float3){0.5, 0.5, 0.5});

        cellRelativeVertexPos[i] = vector_mix(v1[i].cellRelativeVertexPos, v2[i].cellRelativeVertexPos,
                                              (vector_float3){0.5, 0.5, 0.5});
    }
    
    // One normal for the entire face.
    vector_float3 normal = vector_normalize(vector_cross(cellRelativeVertexPos[1]-cellRelativeVertexPos[0],
                                                         cellRelativeVertexPos[2]-cellRelativeVertexPos[0]));
    
    // Select a texture from `texForFace' by examining the normal.
    GSCubeFace dir = determineDirectionFromFaceNormal(normal);
    int tex = texForFace[dir];
    
    for(int i = 0; i < 3; ++i)
    {
        c[i] = vertexColor(v1[i], v2[i], worldPos[i], chunkMinP, normal, voxels, voxelBox);
    }

    for(int i = 0; i < 3; ++i)
    {
        faceVoxel[i] = (v1[i].voxel->type != VOXEL_TYPE_GROUND) ? *v2[i].voxel : *v1[i].voxel;
    }

    for(int i = 0; i < 3; ++i)
    {
        emitVertex(geometry, worldPos[i], cellRelativeVertexPos[i], c[i], tex, normal);
    }
}


static inline void determineTexForFace(GSCubeVertex cube[NUM_CUBE_VERTS], int texForFace[NUM_CUBE_FACES])
{
    // Cube vertices for the six faces of the cube.
    static const size_t adj[NUM_CUBE_FACES][4] = {
        {3,2,1,0}, // TOP
        {4,5,6,7}, // BOTTOM
        {3,2,6,7}, // NORTH
        {3,0,4,7}, // EAST
        {0,1,5,4}, // SOUTH
        {2,1,5,6}, // WEST
    };

    int materialsTop[NUM_CUBE_VERTS];
    int materialsSide[NUM_CUBE_VERTS];

    for(int i = 0; i < NUM_CUBE_VERTS; ++i)
    {
        materialsSide[i] = cube[i].voxel->texSide;
        materialsTop[i] = cube[i].voxel->texTop;
    }

    for(GSCubeFace face = 0; face < NUM_CUBE_FACES; ++face)
    {
        // Indices for this cube face.
        size_t iTL = adj[face][0];
        size_t iTR = adj[face][1];
        size_t iBR = adj[face][2];
        size_t iBL = adj[face][3];

        // Look up the materials for the chosen vertices.
        BOOL top = (face == TOP);
        int sTL = (top ? materialsTop : materialsSide)[iTL];
        int sTR = (top ? materialsTop : materialsSide)[iTR];
        int sBR = (top ? materialsTop : materialsSide)[iBR];
        int sBL = (top ? materialsTop : materialsSide)[iBL];

        // Tile selection algorithm below comes from <http://blog.project-retrograde.com/2013/05/marching-squares/>.
        // 'h' stands for half.
        int hTL = sTL >> 1;
        int hTR = sTR >> 1;
        int hBL = sBL >> 1;
        int hBR = sBR >> 1;
        
        int saddle = ( (sTL & 1) + (sTR & 1) + (sBL & 1) + (sBR & 1) + 1 ) >> 2;
        int shape = (hTL & 1) | (hTR & 1) << 1 | (hBL & 1) << 2 | (hBR & 1) << 3;
        int ring = ( hTL + hTR + hBL + hBR ) >> 2;
        
        int row = (ring << 1) | saddle;
        int col = shape - (ring & 1);
        int idx = row*15+col;
        
        texForFace[face] = idx;
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

    // Select the texture to use on each cube of the face.
    int texForFace[NUM_CUBE_FACES];
    determineTexForFace(cube, texForFace);

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

        addTri(geometry, chunkMinP, voxels, voxelBox, v1, v2, texForFace);
    }
}

static void addQuad(GSTerrainGeometry * _Nonnull geometry,
                    vector_float3 vertices[4],
                    vector_float2 texCoords[4],
                    int tex)
{
    vector_uchar4 c[3];

    for(int i = 0; i < 3; ++i)
    {
        c[i] = 255; // TODO: lighting
    }

    int vertexIndices[6] = {0, 1, 3, 1, 2, 3};
    for(int i = 0; i < 6; ++i)
    {
        vector_float3 p = vertices[vertexIndices[i]];
        vector_float2 uv = texCoords[vertexIndices[i]];

        GSTerrainVertex v = {
            .position = {p.x, p.y, p.z},
            .color = {255, 255, 255, 255},
            .texCoord = {uv.x, uv.y, tex}
        };
        
        GSTerrainGeometryAddVertex(geometry, &v);
    }
}


static inline GSCubeVertex getCubeVertex(vector_float3 chunkMinP,
                                         GSVoxel * _Nonnull voxels,
                                         GSIntAABB voxelBox,
                                         GSTerrainBufferElement * _Nonnull light,
                                         GSIntAABB * _Nonnull lightBox,
                                         vector_float3 cellPos,
                                         vector_float3 cellRelativeVertexPos)
{
    vector_float3 worldPos = cellPos + cellRelativeVertexPos;
    vector_long3 chunkLocalPos = vector_long(worldPos - chunkMinP);
    if (chunkLocalPos.y >= CHUNK_SIZE_Y) {
        return (GSCubeVertex){
            .cellRelativeVertexPos = cellRelativeVertexPos + vector_make(L, L, L),
            .worldPos = worldPos,
            .voxel = &gEmpty,
            .light = CHUNK_LIGHTING_MAX
        };
    } else {
        return (GSCubeVertex){
            .cellRelativeVertexPos = cellRelativeVertexPos + vector_make(L, L, L),
            .worldPos = worldPos,
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
    
    // Get the sub-chunk bounding box and offset to align with the grid cells used.
    GSIntAABB ibounds = GSTerrainGeometrySubchunkBoxInt(chunkMinP, subchunkIndex);

    vector_float3 pos;

    {
        GSFloatAABB marchingCubesBounds = {
            .mins = vector_float(ibounds.mins) + vector_make(L, L, L),
            .maxs = vector_float(ibounds.maxs) + vector_make(L, L, L)
        };
        
        // Marching Cubes isosurface extraction for GROUND blocks.
        FOR_BOX(pos, marchingCubesBounds)
        {
            GSCubeVertex cube[NUM_CUBE_VERTS] = {
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(-L, -L, +L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(+L, -L, +L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(+L, -L, -L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(-L, -L, -L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(-L, +L, +L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(+L, +L, +L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(+L, +L, -L)),
                getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(-L, +L, -L))
            };
            
            polygonizeGridCell(geometry, cube, chunkMinP, voxels, &voxelBox);
        }
    }

    {
        static const vector_float3 normals[NUM_CUBE_FACES] = {
            (vector_float3){ 0, +1,  0}, // TOP
            (vector_float3){ 0, -1,  0}, // BOTTOM
            (vector_float3){ 0,  0, +1}, // NORTH
            (vector_float3){+1,  0,  0}, // EAST
            (vector_float3){ 0,  0, -1}, // SOUTH
            (vector_float3){-1,  0,  0}  // WEST
        };
        
        static const vector_float3 tangents[NUM_CUBE_FACES] = {
            (vector_float3){ 0,  0, +1}, // TOP
            (vector_float3){-1,  0,  0}, // BOTTOM
            (vector_float3){+1,  0,  0}, // NORTH
            (vector_float3){ 0,  0, -1}, // EAST
            (vector_float3){-1,  0,  0}, // SOUTH
            (vector_float3){ 0,  0, +1}  // WEST
        };
        
        static const vector_float3 bitangents[NUM_CUBE_FACES] = {
            (vector_float3){+1,  0,  0}, // TOP
            (vector_float3){ 0,  0, -1}, // BOTTOM
            (vector_float3){ 0, +1,  0}, // NORTH
            (vector_float3){ 0, +1,  0}, // EAST
            (vector_float3){ 0, +1,  0}, // SOUTH
            (vector_float3){ 0, +1,  0}  // WEST
        };
        
        static const vector_float3 cornerSelect[4] = {
            // n   b   t
            { +1, +1, +1}, // Top Right
            { +1, -1, +1}, // Top Left
            { +1, -1, -1}, // Bottom Left
            { +1, +1, -1}  // Bottom Right
        };
        
        GSFloatAABB bounds = {
            .mins = vector_float(ibounds.mins),
            .maxs = vector_float(ibounds.maxs)
        };
        
        FOR_BOX(pos, bounds)
        {
            GSCubeVertex central = getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, vector_make(0, 0, 0));
            
            if (central.voxel->type != VOXEL_TYPE_WALL) {
                continue;
            }
            
            GSCubeVertex adjacentCells[NUM_CUBE_FACES];
            
            for(int i = 0; i < NUM_CUBE_FACES; ++i)
            {
                adjacentCells[i] = getCubeVertex(chunkMinP, voxels, voxelBox, light, lightBox, pos, normals[i]);
            }
            
            for(int i = 0; i < NUM_CUBE_FACES; ++i)
            {
                if (adjacentCells[i].voxel->type != VOXEL_TYPE_WALL) {
                    vector_float3 n = normals[i];
                    vector_float3 t = tangents[i];
                    vector_float3 b = bitangents[i];
                    vector_float3 vertices[4];
                    vector_float2 texCoords[4];
                    
                    for(int f = 0; f < 4; ++f)
                    {
                        vertices[f] = pos + L*(n * cornerSelect[f].x + t * cornerSelect[f].y + b * cornerSelect[f].z);
                        texCoords[f] = (vector_float2){cornerSelect[f].y*0.5f+0.5f, 1-cornerSelect[f].z*0.5f+0.5f};
                    }
                    
                    addQuad(geometry, vertices, texCoords, 104);
                }
            }
        }
    }
}
