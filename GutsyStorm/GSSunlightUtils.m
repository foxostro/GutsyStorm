//
//  GSSunlightUtils.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSSunlightUtils.h"

// Find the elevation of the highest opaque block.
long GSFindElevationOfHighestOpaqueBlock(GSVoxel * _Nonnull voxels, size_t voxelCount,
                                       vector_long3 voxelMinP, vector_long3 voxelMaxP)
{
    assert(voxels);
    assert(voxelCount);
    
    vector_long3 p;
    long highest = voxelMaxP.y;
    
    FOR_BOX(p, voxelMinP, voxelMaxP)
    {
        GSVoxel voxel = {0};
        size_t voxelIdx = INDEX_BOX(p, voxelMinP, voxelMaxP);
        if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
            voxel = voxels[voxelIdx];
        }
        
        if (voxel.opaque) {
            highest = MAX(highest, p.y);
        }
    }
    
    return highest;
}

void GSSunlightSeed(GSVoxel * _Nonnull voxels, size_t voxelCount,
          vector_long3 voxelMinP, vector_long3 voxelMaxP,
          GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
          vector_long3 sunlightMinP, vector_long3 sunlightMaxP,
          vector_long3 seedMinP, vector_long3 seedMaxP)
{
    assert(voxels);
    assert(voxelCount);
    assert(sunlight);
    assert(sunCount);
    
    vector_long3 p;
    
    // Seed phase.
    // Seed the sunlight buffer with light at outside non-opaque blocks.
    // Also, find the elevation of the highest opaque block.
    FOR_BOX(p, seedMinP, seedMaxP)
    {
        GSVoxel voxel = {0};
        size_t voxelIdx = INDEX_BOX(p, voxelMinP, voxelMaxP);
        if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
            voxel = voxels[voxelIdx];
        }
        
        BOOL directlyLit = (!voxel.opaque) && (voxel.outside);
        
        if (directlyLit) {
            size_t sunlightIdx = INDEX_BOX(p, sunlightMinP, sunlightMaxP);
            assert(sunlightIdx < sunCount);
            sunlight[sunlightIdx] = CHUNK_LIGHTING_MAX;
        }
    }
}

void GSSunlightBlur(GSVoxel * _Nonnull voxels, size_t voxelCount,
                    vector_long3 voxelMinP, vector_long3 voxelMaxP,
                    GSTerrainBufferElement * _Nonnull sunlight, size_t sunCount,
                    vector_long3 sunlightMinP, vector_long3 sunlightMaxP,
                    vector_long3 blurMinP, vector_long3 blurMaxP,
                    vector_long3 * _Nullable outAffectedAreaMinP, vector_long3 * _Nullable outAffectedAreaMaxP)
{
    assert(voxels);
    assert(voxelCount);
    assert(sunlight);
    assert(sunCount);
    
    vector_long3 actualAffectedAreaMinP = blurMaxP, actualAffectedAreaMaxP = blurMinP;

    // Blur phase.
    // Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
    // Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
    // Set the blocks we find to the next lower light level.
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        vector_long3 p;
        FOR_BOX(p, blurMinP, blurMaxP)
        {
            GSVoxel voxel = {0};
            size_t voxelIdx = INDEX_BOX(p, voxelMinP, voxelMaxP);
            if (voxelIdx < voxelCount) { // Voxels that are out of bounds are assumed to be set to zero.
                voxel = voxels[voxelIdx];
            }
            
            if(voxel.opaque || voxel.outside) {
                continue;
            }
            
            BOOL adj = GSSunlightAdjacent(p, lightLevel,
                                            voxels, voxelMinP, voxelMaxP,
                                            sunlight, sunlightMinP, sunlightMaxP);
            
            if(adj) {
                size_t sunlightIdx = INDEX_BOX(p, sunlightMinP, sunlightMaxP);
                assert(sunlightIdx < sunCount);
                GSTerrainBufferElement *value = &sunlight[sunlightIdx];

                if ((lightLevel - 1) > (*value)) {
                    *value = lightLevel - 1;
                    
                    actualAffectedAreaMinP.x = MIN(actualAffectedAreaMinP.x, p.x);
                    actualAffectedAreaMinP.y = MIN(actualAffectedAreaMinP.y, p.y);
                    actualAffectedAreaMinP.z = MIN(actualAffectedAreaMinP.z, p.z);
                    
                    actualAffectedAreaMaxP.x = MAX(actualAffectedAreaMaxP.x, p.x);
                    actualAffectedAreaMaxP.y = MAX(actualAffectedAreaMaxP.y, p.y);
                    actualAffectedAreaMaxP.z = MAX(actualAffectedAreaMaxP.z, p.z);
                }
            }
        }
    }
    
    if (outAffectedAreaMinP) {
        *outAffectedAreaMinP = actualAffectedAreaMinP;
    }
    
    if (outAffectedAreaMaxP) {
        *outAffectedAreaMaxP = actualAffectedAreaMaxP;
    }
}

BOOL GSSunlightAdjacent(vector_long3 p, int lightLevel,
                          GSVoxel * _Nonnull voxels,
                          vector_long3 voxelMinP, vector_long3 voxelMaxP,
                          GSTerrainBufferElement * _Nonnull sunlight,
                          vector_long3 sunlightMinP, vector_long3 sunlightMaxP)
{
    assert(voxels);
    assert(sunlight);
    
    for(GSVoxelFace i=0; i<FACE_NUM_FACES; ++i)
    {
        vector_long3 a = p + GSOffsetForVoxelFace[i];
        
        if(a.x < -CHUNK_SIZE_X || a.x >= (2*CHUNK_SIZE_X) ||
           a.z < -CHUNK_SIZE_Z || a.z >= (2*CHUNK_SIZE_Z) ||
           a.y < 0 || a.y >= CHUNK_SIZE_Y) {
            continue; // The point is out of bounds, so bail out.
        }
        
        size_t voxelIdx = INDEX_BOX(a, voxelMinP, voxelMaxP);
        if(voxels[voxelIdx].opaque) {
            continue;
        }
        
        size_t sunlightIdx = INDEX_BOX(a, sunlightMinP, sunlightMaxP);
        if(sunlight[sunlightIdx] == lightLevel) {
            return YES;
        }
    }
    
    return NO;
}
