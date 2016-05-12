//
//  GSSunlightUtils.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSVoxel.h"
#import "GSTerrainBuffer.h"
#import "GSAABB.h"

long GSFindElevationOfHighestOpaqueBlock(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB * _Nonnull voxelBox);

void GSSunlightSeed(GSVoxel * _Nonnull voxels, size_t voxelCount,
                    GSIntAABB * _Nonnull voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                    GSIntAABB * _Nonnull sunlightBox,
                    GSIntAABB * _Nonnull seedBox);

void GSSunlightBlur(GSVoxel * _Nonnull voxels, size_t voxelCount,
                    GSIntAABB * _Nonnull voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                    GSIntAABB * _Nonnull sunlightBox,
                    GSIntAABB * _Nonnull blurBox,
                    GSIntAABB * _Nullable affectedRegion);

BOOL GSSunlightAdjacent(vector_long3 p, int lightLevel,
                        GSVoxel * _Nonnull voxels, size_t voxCount,
                        GSIntAABB * _Nonnull voxelBox,
                        GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                        GSIntAABB * _Nonnull sunlightBox);
