//
//  GSTerrainGeometryGenerator.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGeometryGeneratorInternal.h"
#import "GSTerrainGeometryMarchingCubes.h"
#import "GSTerrainGeometryBlockGen.h"
#import "GSVoxel.h" // for CHUNK_SIZE_Y


_Static_assert(CHUNK_SIZE_Y % GSNumGeometrySubChunks == 0,
               "Chunk size must be evenly divisible by the number of geometry sub-chunks");


GSFloatAABB GSTerrainGeometrySubchunkBoxFloat(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB result;
    result.mins = minP + (vector_float3){0, CHUNK_SIZE_Y * i / GSNumGeometrySubChunks, 0};
    result.maxs = result.mins + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y / GSNumGeometrySubChunks, CHUNK_SIZE_Z};
    return result;
}


GSIntAABB GSTerrainGeometrySubchunkBoxInt(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB box = GSTerrainGeometrySubchunkBoxFloat(minP, i);
    return (GSIntAABB){ vector_long(box.mins), vector_long(box.maxs) };
}


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               GSTerrainBufferElement * _Nonnull light,
                               GSIntAABB * _Nonnull lightBox,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex)
{
    GSIntAABB ibounds = GSTerrainGeometrySubchunkBoxInt(chunkMinP, subchunkIndex);
    GSTerrainGeometryMarchingCubes(geometry, voxels, voxelBox, light, lightBox, chunkMinP, ibounds);
    GSTerrainGeometryBlockGen(geometry, voxels, voxelBox, chunkMinP, ibounds);
}
