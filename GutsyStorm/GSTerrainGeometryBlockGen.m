//
//  GSTerrainGeometryBlockGen.m
//  GutsyStorm
//
//  Created by Andrew Fox on 6/5/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSTerrainGeometryBlockGen.h"


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


static const vector_float2 cornerSelect[4] = {
    // b   t
    { +1, +1}, // Top Right
    { -1, +1}, // Top Left
    { -1, -1}, // Bottom Left
    { +1, -1}  // Bottom Right
};


static void addQuad(GSTerrainGeometry * _Nonnull geometry,
                    vector_float3 vertices[4],
                    vector_float2 texCoords[4],
                    int tex)
{
    // TODO: apply lighting to the quad's vertices
    vector_uchar4 colors[4] = {
        {255, 255, 255, 255},
        {255, 255, 255, 255},
        {255, 255, 255, 255},
        {255, 255, 255, 255}
    };

    int vertexIndices[6] = {0, 1, 3, 1, 2, 3};
    for(int i = 0; i < 6; ++i)
    {
        int idx = vertexIndices[i];
        vector_float3 pos = vertices[idx];
        vector_float2 texCoord = texCoords[idx];
        vector_uchar4 color = colors[idx];

        GSTerrainVertex v = {
            .position = {pos.x, pos.y, pos.z},
            .color = {color.x, color.y, color.z, color.w},
            .texCoord = {texCoord.x, texCoord.y, tex}
        };

        GSTerrainGeometryAddVertex(geometry, &v);
    }
}


static inline int getAdjacentVoxelType(GSCubeFace dir, vector_float3 pos, vector_float3 chunkMinP,
                                       GSVoxel * _Nonnull voxels, GSIntAABB voxelBox)
{
    int adjacentVoxelType;
    vector_long3 chunkLocalPos = vector_long(pos + normals[dir] - chunkMinP);

    if (chunkLocalPos.y < CHUNK_SIZE_Y && chunkLocalPos.y >= 0) {
        adjacentVoxelType = voxels[INDEX_BOX(chunkLocalPos, voxelBox)].type;
    } else {
        adjacentVoxelType = VOXEL_TYPE_EMPTY;
    }

    return adjacentVoxelType;
}

static inline int getTextureIndex(GSVoxelTexture tex)
{
    // These values depend on the structure of the texture atlas in terrain.png.
    switch(tex)
    {
        case VOXEL_TEX_WATER_0: return 0;
        case VOXEL_TEX_WATER_1: return 15;
        case VOXEL_TEX_DIRT_0:  return 44;
        case VOXEL_TEX_DIRT_1:  return 59;
        case VOXEL_TEX_GRASS_0: return 60;
        case VOXEL_TEX_GRASS_1: return 75;
        case VOXEL_TEX_STONE_0: return 104;
        case VOXEL_TEX_STONE_1: return 119;
        default:
            assert(false);
            return 0;
    }
}

void GSTerrainGeometryBlockGen(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               vector_float3 chunkMinP,
                               GSIntAABB ibounds)
{
    assert(geometry);
    assert(voxels);
    
    vector_float3 pos;
    GSFloatAABB bounds = { .mins = vector_float(ibounds.mins), .maxs = vector_float(ibounds.maxs) };

    FOR_BOX(pos, bounds)
    {
        GSVoxel centerVoxel = voxels[INDEX_BOX(vector_long(pos - chunkMinP), voxelBox)];
        
        if (centerVoxel.type != VOXEL_TYPE_WALL) {
            continue;
        }
        
        for(int i = 0; i < NUM_CUBE_FACES; ++i)
        {
            if (getAdjacentVoxelType(i, pos, chunkMinP, voxels, voxelBox) == VOXEL_TYPE_WALL) {
                continue;
            }
            
            vector_float3 n = normals[i];
            vector_float3 t = tangents[i];
            vector_float3 b = bitangents[i];
            vector_float3 vertices[4];
            vector_float2 texCoords[4];
            
            for(int f = 0; f < 4; ++f)
            {
                vertices[f] = pos + L*(n + t * cornerSelect[f].x + b * cornerSelect[f].y);
                texCoords[f] = (vector_float2){cornerSelect[f].x*0.5f+0.5f, 1-cornerSelect[f].y*0.5f+0.5f};
            }
            
            addQuad(geometry, vertices, texCoords, getTextureIndex(VOXEL_TEX_STONE_0));
        }
    }
}
