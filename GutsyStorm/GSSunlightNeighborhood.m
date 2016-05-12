//
//  GSSunlightNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSSunlightNeighborhood.h"
#import "GSSunlightUtils.h"
#import "GSAABB.h"
#import "GSBox.h"

@implementation GSSunlightNeighborhood

- (nonnull GSTerrainBufferElement *)newSunlightBufferReturningCount:(size_t *)outCount
{
    GSIntAABB nSunBox;
    nSunBox.mins = GSCombinedMinP - GSMakeIntegerVector3(1, 0, 1);
    nSunBox.maxs = GSCombinedMaxP + GSMakeIntegerVector3(1, 0, 1);
    vector_long3 nSunDim = nSunBox.maxs - nSunBox.mins;

    size_t count = nSunDim.x * nSunDim.y * nSunDim.z;

    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    GSTerrainBufferElement *combinedSunlightData = malloc(count*sizeof(GSTerrainBufferElement));
    if(!combinedSunlightData) {
        [NSException raise:NSMallocException format:@"Failed to allocate memory for combinedSunlightData."];
    }
    
    static long offsetsX[CHUNK_NUM_NEIGHBORS];
    static long offsetsZ[CHUNK_NUM_NEIGHBORS];
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        for(GSVoxelNeighborIndex i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            offsetsX[i] = offset.x;
            offsetsZ[i] = offset.z;
        }
    });
    
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSChunkSunlightData *neighbor = (GSChunkSunlightData *)[self neighborAtIndex:i];
        GSTerrainBufferElement *srcData = [neighbor.sunlight data];
        vector_long3 srcDim = neighbor.sunlight.dimensions;

        long offsetX = offsetsX[i];
        long offsetZ = offsetsZ[i];

        GSIntAABB neighborBox;
        neighborBox.mins = -(neighbor.sunlight.offsetFromChunkLocalSpace);
        neighborBox.maxs = neighborBox.mins + srcDim;
        
        vector_long3 p;
        FOR_Y_COLUMN_IN_BOX(p, neighborBox)
        {
            size_t dstIdx = INDEX_BOX(GSMakeIntegerVector3(p.x+offsetX, p.y, p.z+offsetZ), nSunBox);
            size_t srcIdx = INDEX_BOX(p, neighborBox);

            assert(dstIdx < count);
            assert(srcIdx < (srcDim.x * srcDim.y * srcDim.z));

            memcpy(&combinedSunlightData[dstIdx], &srcData[srcIdx], srcDim.y * sizeof(combinedSunlightData[0]));
        }
    }
    
    if (count) {
        *outCount = count;
    }
    
    return combinedSunlightData;
}

- (nonnull GSTerrainBuffer *)newSunlightBufferWithEditAtPoint:(vector_float3)editPos
                                                removingLight:(BOOL)removingLight
                                               affectedRegion:(GSIntAABB * _Nullable)outAffectedBox
{
    static const int blurSize = CHUNK_LIGHTING_MAX + 1;
    static const vector_long3 border = (vector_long3){1, 0, 1};

    GSIntAABB voxelBox = { .mins = GSCombinedMinP, .maxs = GSCombinedMaxP };

    GSIntAABB nSunBox;
    nSunBox.mins = voxelBox.mins - border;
    nSunBox.maxs = voxelBox.maxs + border;

    vector_long3 nSunDim = nSunBox.maxs - nSunBox.mins;
    vector_long3 p; // loop counter
    
    size_t voxelCount = 0;
    GSVoxel *voxels = [self.voxelNeighborhood newVoxelBufferReturningCount:&voxelCount];
    
    // Populate the sunlight buffer with existing sunlight values from all the neighboring chunks.
    size_t nSunCount;
    GSTerrainBufferElement *sunlight = [self newSunlightBufferReturningCount:&nSunCount];

    // Clear sunlight values in the region affected by the edit.
    GSChunkSunlightData *center = [self neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    assert(center);
    vector_long3 editPosClp = GSCastToIntegerVector3(editPos - center.minP);
    
    GSIntAABB workBox;
    workBox.mins = editPosClp - GSMakeIntegerVector3(blurSize, 0, blurSize);
    workBox.mins.y = 0;
    
    workBox.maxs = editPosClp + GSMakeIntegerVector3(blurSize, blurSize, blurSize);
    workBox.maxs.y = MIN(workBox.maxs.y, GSChunkSizeIntVec3.y);

    // If we're removing light then we need to zero out the blur region first.
    if (removingLight) {
        GSIntAABB adjustedWorkBox = { .mins = workBox.mins + border, .maxs = workBox.maxs - border };
        FOR_BOX(p, adjustedWorkBox)
        {
            size_t srcIdx = INDEX_BOX(p, nSunBox);
            assert(srcIdx < (nSunDim.x * nSunDim.y * nSunDim.z));
            sunlight[srcIdx] = 0;
        }
    }

    GSSunlightSeed(voxels, voxelCount, &voxelBox,
                   sunlight, nSunCount, &nSunBox,
                   &workBox);

    GSIntAABB affectedBox;
    GSSunlightBlur(voxels, voxelCount, &voxelBox,
                   sunlight, nSunCount, &nSunBox,
                   &workBox,
                   &affectedBox);
    
    // If sunlight was already in equilibrium state when we performed the sunlight blur then set the
    // affected area to a 3x3x3 cube surrounding the edit point. This will ensure geometry gets updated later.
    if((affectedBox.maxs.x <= affectedBox.mins.x) || (affectedBox.maxs.y <= affectedBox.mins.y) || (affectedBox.maxs.z <= affectedBox.mins.z)) {
        affectedBox.mins = editPosClp - GSMakeIntegerVector3(1, 1, 1);
        affectedBox.mins.y = MAX(affectedBox.mins.y, 0);
        
        affectedBox.maxs = editPosClp + GSMakeIntegerVector3(1, 1, 1);
        affectedBox.maxs.y = MIN(affectedBox.maxs.y, GSChunkSizeIntVec3.y);
    }

    if (outAffectedBox) {
        *outAffectedBox = affectedBox;
    }

    free(voxels);
    
    GSTerrainBuffer *result = [[GSTerrainBuffer alloc] initWithDimensions:nSunDim copyUnalignedData:sunlight];
    
    free(sunlight);
    
    return result;
}

@end
