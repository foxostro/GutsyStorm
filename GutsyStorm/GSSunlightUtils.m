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
long GSFindElevationOfHighestOpaqueBlock(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB * _Nonnull voxelBox)
{
    assert(voxels);
    assert(voxelCount);
    assert(voxelBox);
    
    vector_long3 p;
    long highest = voxelBox->maxs.y;
    
    FOR_BOX(p, *voxelBox)
    {
        GSVoxel voxel = {0};
        size_t voxelIdx = INDEX_BOX(p, *voxelBox);
        if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
            voxel = voxels[voxelIdx];
        }

        if (voxel.opaque) {
            highest = MAX(highest, p.y);
        }
    }
    
    return highest;
}

void GSSunlightSeed(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB * _Nonnull voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount, GSIntAABB * _Nonnull sunlightBox,
                    GSIntAABB * _Nonnull seedBox)
{
    assert(voxels);
    assert(voxelCount);
    assert(sunlight);
    assert(sunCount);
    assert(sunlightBox);
    assert(seedBox);
    
    vector_long3 p;
    
    // Seed phase.
    // Seed the sunlight buffer with light at outside non-opaque blocks.
    // Also, find the elevation of the highest opaque block.
    FOR_BOX(p, *seedBox)
    {
        size_t voxelIdx = INDEX_BOX(p, *voxelBox);

        if (voxelIdx < voxelCount) {
            GSVoxel voxel = voxels[voxelIdx];
            BOOL directlyLit = (!voxel.opaque) && (voxel.outside || voxel.torch);

            if (directlyLit) {
                size_t sunlightIdx = INDEX_BOX(p, *sunlightBox);
                assert(sunlightIdx < sunCount);
                sunlight[sunlightIdx] = CHUNK_LIGHTING_MAX;
            }
        }
    }
}

void GSSunlightBlur(GSVoxel * _Nonnull voxels, size_t voxelCount, GSIntAABB * _Nonnull voxelBox,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount, GSIntAABB * _Nonnull sunlightBox,
                    GSIntAABB * _Nonnull blurBox,
                    GSIntAABB * _Nullable outAffectedRegion)
{
    assert(voxels);
    assert(voxelCount);
    assert(voxelBox);
    assert(sunlight);
    assert(sunCount);
    assert(sunlightBox);
    assert(blurBox);
    
    GSIntAABB actualAffectedRegion = { .mins = blurBox->maxs, .maxs = blurBox->mins };

    // Blur phase.
    // Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
    // Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
    // Set the blocks we find to the next lower light level.
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        vector_long3 p;
        FOR_BOX(p, *blurBox)
        {
            GSVoxel voxel = {0};
            size_t voxelIdx = INDEX_BOX(p, *voxelBox);
            if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
                voxel = voxels[voxelIdx];
            }
            
            if(voxel.opaque || voxel.outside) {
                continue;
            }
            
            BOOL adj = GSSunlightAdjacent(p, lightLevel,
                                          voxels, voxelCount, *voxelBox,
                                          sunlight, sunCount, *sunlightBox);

            if(adj) {
                size_t sunlightIdx = INDEX_BOX(p, *sunlightBox);
                assert(sunlightIdx < sunCount);
                GSTerrainBufferElement *value = &sunlight[sunlightIdx];

                if ((lightLevel - 1) > (*value)) {
                    *value = lightLevel - 1;
                    
                    actualAffectedRegion.mins.x = MIN(actualAffectedRegion.mins.x, p.x);
                    actualAffectedRegion.mins.y = MIN(actualAffectedRegion.mins.y, p.y);
                    actualAffectedRegion.mins.z = MIN(actualAffectedRegion.mins.z, p.z);
                    
                    actualAffectedRegion.maxs.x = MAX(actualAffectedRegion.maxs.x, p.x);
                    actualAffectedRegion.maxs.y = MAX(actualAffectedRegion.maxs.y, p.y);
                    actualAffectedRegion.maxs.z = MAX(actualAffectedRegion.maxs.z, p.z);
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
        
        if(a.x < sunlightBox.mins.x || a.x >= sunlightBox.maxs.x ||
           a.z < sunlightBox.mins.z || a.z >= sunlightBox.maxs.z ||
           a.y < sunlightBox.mins.y || a.y >= sunlightBox.maxs.y) {
            continue; // The point is out of bounds, so bail out.
        }
        
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
