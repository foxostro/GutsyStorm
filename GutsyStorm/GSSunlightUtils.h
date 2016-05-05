//
//  GSSunlightUtils.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSVoxel.h"
#import "GSTerrainBuffer.h"


long GSFindElevationOfHighestOpaqueBlock(GSVoxel * _Nonnull voxels, size_t voxelCount,
                                         vector_long3 voxelMinP, vector_long3 voxelMaxP);

void GSSunlightSeed(GSVoxel * _Nonnull voxels, size_t voxelCount,
                    vector_long3 voxelMinP, vector_long3 voxelMaxP,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                    vector_long3 sunlightMinP, vector_long3 sunlightMaxP,
                    vector_long3 seedMinP, vector_long3 seedMaxP);

void GSSunlightBlur(GSVoxel * _Nonnull voxels, size_t voxelCount,
                    vector_long3 voxelMinP, vector_long3 voxelMaxP,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                    vector_long3 sunlightMinP, vector_long3 sunlightMaxP,
                    vector_long3 blurMinP, vector_long3 blurMaxP,
                    vector_long3 * _Nullable affectedAreaMinP, vector_long3 * _Nullable affectedAreaMaxP);

BOOL GSSunlightAdjacent(vector_long3 p, int lightLevel,
                        GSVoxel * _Nonnull voxels,
                        vector_long3 voxelMinP, vector_long3 voxelMaxP,
                        GSTerrainBufferElement * _Nonnull sunlight,
                        vector_long3 sunlightMinP, vector_long3 sunlightMaxP);
