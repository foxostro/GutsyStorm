//
//  GSSunlightUtils.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSSunlightUtils.h"
#import "GSBox.h"

// Find the elevation of the highest opaque block.
long GSFindElevationOfHighestOpaqueBlock(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB voxelBox)
{
    assert(voxels);
    assert(voxelCount);
    
    vector_long3 p;
    long highest = voxelBox.maxs.y;
    
    FOR_BOX(p, voxelBox)
    {
        GSVoxel voxel = {0};
        size_t voxelIdx = INDEX_BOX(p, voxelBox);
        if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
            voxel = voxels[voxelIdx];
        }

        if (voxel.opaque) {
            highest = MAX(highest, p.y);
        }
    }
    
    return highest;
}

void GSSunlightSeed(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount, GSIntAABB sunlightBox,
                    GSIntAABB seedBox)
{
    assert(voxels);
    assert(voxelCount);
    assert(sunlight);
    assert(sunCount);
    
    vector_long3 p;
    
    // Seed phase.
    // Seed the sunlight buffer with light at outside non-opaque blocks.
    // Also, find the elevation of the highest opaque block.
    FOR_BOX(p, seedBox)
    {
        size_t voxelIdx = INDEX_BOX(p, voxelBox);

        if (voxelIdx < voxelCount) {
            GSVoxel voxel = voxels[voxelIdx];
            BOOL directlyLit = (!voxel.opaque) && (voxel.outside || voxel.torch);

            if (directlyLit) {
                size_t sunlightIdx = INDEX_BOX(p, sunlightBox);
                assert(sunlightIdx < sunCount);
                sunlight[sunlightIdx] = CHUNK_LIGHTING_MAX;
            }
        }
    }
}

void GSSunlightBlur(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount, GSIntAABB sunlightBox,
                    GSIntAABB blurBox,
                    vector_long3 editPosClp,
                    GSIntAABB * _Nullable outAffectedRegion)
{
    assert(voxels);
    assert(voxelCount);
    assert(sunlight);
    assert(sunCount);
    
    GSIntAABB actualAffectedRegion = { .mins = editPosClp, .maxs = editPosClp };
    
    blurBox.mins = vector_max(blurBox.mins, sunlightBox.mins + GSMakeIntegerVector3(1, 1, 1));
    blurBox.maxs = vector_min(blurBox.maxs, sunlightBox.maxs - GSMakeIntegerVector3(1, 1, 1));

    // Blur phase.
    // Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
    // Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
    // Set the blocks we find to the next lower light level.
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        vector_long3 p;
        FOR_BOX(p, blurBox)
        {
            GSVoxel voxel = voxels[INDEX_BOX(p, voxelBox)];
            
            if(voxel.opaque || voxel.outside) {
                continue;
            }
            
            BOOL adj = GSSunlightAdjacent(p, lightLevel,
                                          voxels, voxelCount, voxelBox,
                                          sunlight, sunCount, sunlightBox);

            if(adj) {
                size_t sunlightIdx = INDEX_BOX(p, sunlightBox);
                assert(sunlightIdx < sunCount);
                GSTerrainBufferElement *value = &sunlight[sunlightIdx];

                if ((lightLevel - 1) > (*value)) {
                    *value = lightLevel - 1;
                    
                    actualAffectedRegion.mins = vector_min(actualAffectedRegion.mins, p);
                    actualAffectedRegion.maxs = vector_max(actualAffectedRegion.maxs, p);
                }
            }
        }
    }
    
    if (outAffectedRegion) {
        *outAffectedRegion = actualAffectedRegion;
    }
}

BOOL GSSunlightAdjacent(vector_long3 p, int lightLevel,
                        GSVoxel * _Nonnull voxels, size_t voxCount,
                        GSIntAABB voxelBox,
                        GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                        GSIntAABB sunlightBox)
{
    assert(voxels);
    assert(voxCount);
    assert(sunlight);
    assert(sunCount);

    for(GSVoxelFace i=0; i<FACE_NUM_FACES; ++i)
    {
        vector_long3 a = p + GSOffsetForVoxelFace[i];
        
        size_t voxelIdx = INDEX_BOX(a, voxelBox);
        assert(voxelIdx < voxCount);
        
        size_t sunlightIdx = INDEX_BOX(a, sunlightBox);
        assert(sunlightIdx < sunCount);
        if (!(voxels[voxelIdx].opaque) && (sunlight[sunlightIdx] == lightLevel)) {
            return YES;
        }
    }
    
    return NO;
}
