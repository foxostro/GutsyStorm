//
//  GSTerrainGeometryGenerator.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>

#import "GSVoxel.h" // for CHUNK_SIZE_Y
#import "GSAABB.h"
#import "GSTerrainBuffer.h" // for GSTerrainBufferElement
#import "GSTerrainVertex.h"
#import "GSTerrainGeometry.h"


@class GSChunkSunlightData;


#define GSNumGeometrySubChunks (16)
_Static_assert(CHUNK_SIZE_Y % GSNumGeometrySubChunks == 0,
               "Chunk size must be evenly divisible by the number of geometry sub-chunks");


static inline GSFloatAABB GSTerrainGeometrySubchunkBoxFloat(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB result;
    result.mins = minP + (vector_float3){0, CHUNK_SIZE_Y * i / GSNumGeometrySubChunks, 0};
    result.maxs = result.mins + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y / GSNumGeometrySubChunks, CHUNK_SIZE_Z};
    return result;
}


static inline GSIntAABB GSTerrainGeometrySubchunkBoxInt(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB box = GSTerrainGeometrySubchunkBoxFloat(minP, i);
    return (GSIntAABB){ vector_long(box.mins), vector_long(box.maxs) };
}


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               GSTerrainBufferElement * _Nonnull light,
                               GSIntAABB lightBox,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex);
