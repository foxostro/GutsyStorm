//
//  GSTerrainGeometryGenerator.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>

#import "GSAABB.h"
#import "GSTerrainBuffer.h" // for GSTerrainBufferElement
#import "GSTerrainGeometry.h"


@class GSChunkSunlightData;


#define GSNumGeometrySubChunks (16)


GSFloatAABB GSTerrainGeometrySubchunkBoxFloat(vector_float3 minP, NSUInteger i);
GSIntAABB GSTerrainGeometrySubchunkBoxInt(vector_float3 minP, NSUInteger i);


void GSTerrainGeometryGenerate(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               GSTerrainBufferElement * _Nonnull light,
                               GSIntAABB * _Nonnull lightBox,
                               vector_float3 chunkMinP,
                               NSUInteger subchunkIndex);
