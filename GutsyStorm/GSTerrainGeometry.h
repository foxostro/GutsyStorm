//
//  GSTerrainGeometry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>

#import "GSVoxel.h" // for CHUNK_SIZE_Y
#import "GSAABB.h"
#import "GSTerrainVertex.h"


@class GSChunkSunlightData;


#define GSNumGeometrySubChunks (16)
_Static_assert(CHUNK_SIZE_Y % GSNumGeometrySubChunks == 0,
               "Chunk size must be evenly divisible by the number of geometry sub-chunks");


static inline GSFloatAABB GSGeometrySubchunkBoxFloat(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB result;
    result.mins = minP + (vector_float3){0, CHUNK_SIZE_Y * i / GSNumGeometrySubChunks, 0};
    result.maxs = result.mins + (vector_float3){CHUNK_SIZE_X, CHUNK_SIZE_Y / GSNumGeometrySubChunks, CHUNK_SIZE_Z};
    return result;
}


static inline GSIntAABB GSGeometrySubchunkBoxInt(vector_float3 minP, NSUInteger i)
{
    GSFloatAABB box = GSGeometrySubchunkBoxFloat(minP, i);
    return (GSIntAABB){ vector_long(box.mins), vector_long(box.maxs) };
}


typedef struct
{
    GSTerrainVertex * _Nullable vertices;
    size_t capacity;
    size_t count;
} GSTerrainGeometry;


GSTerrainGeometry * _Nonnull GSTerrainGeometryCreate(GSChunkSunlightData * _Nonnull sunlight,
                                                     vector_float3 chunkMinP, NSUInteger i);
void GSTerrainGeometryDestroy(GSTerrainGeometry * _Nullable geometry);
GSTerrainGeometry * _Nonnull GSTerrainGeometryCopy(GSTerrainGeometry * _Nonnull original);
void GSTerrainGeometryAddVertex(GSTerrainGeometry * _Nonnull geometry, GSTerrainVertex vertex);
