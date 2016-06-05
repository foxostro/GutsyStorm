//
//  GSTerrainGeometryBlockGen.m
//  GutsyStorm
//
//  Created by Andrew Fox on 6/5/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
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


void GSTerrainGeometryBlockGen(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               vector_float3 chunkMinP,
                               GSIntAABB ibounds)
{
    assert(geometry);
    assert(voxels);
    
    GSFloatAABB bounds = {
        .mins = vector_float(ibounds.mins),
        .maxs = vector_float(ibounds.maxs)
    };
    
    vector_float3 pos;
    FOR_BOX(pos, bounds)
    {
        GSVoxel centerVoxel = voxels[INDEX_BOX(vector_long(pos - chunkMinP), voxelBox)];
        
        if (centerVoxel.type != VOXEL_TYPE_WALL) {
            continue;
        }
        
        for(int i = 0; i < NUM_CUBE_FACES; ++i)
        {
            GSVoxel adjacentVoxel = voxels[INDEX_BOX(vector_long(pos + normals[i] - chunkMinP), voxelBox)];
            
            if (adjacentVoxel.type == VOXEL_TYPE_WALL) {
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
            
            addQuad(geometry, vertices, texCoords, 104);
        }
    }
}
