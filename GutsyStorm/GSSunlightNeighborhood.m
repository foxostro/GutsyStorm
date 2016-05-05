//
//  GSSunlightNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSSunlightNeighborhood.h"
#import "GSSunlightUtils.h"

@implementation GSSunlightNeighborhood

- (nonnull GSTerrainBufferElement *)newSunlightBufferReturningCount:(size_t *)outCount
{
    vector_long3 nSunMinP = GSCombinedMinP - GSMakeIntegerVector3(1, 0, 1);
    vector_long3 nSunMaxP = GSCombinedMaxP + GSMakeIntegerVector3(1, 0, 1);
    vector_long3 nSunDim = nSunMaxP - nSunMinP;

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
        
        vector_long3 p, a, b;
        a = -(neighbor.sunlight.offsetFromChunkLocalSpace);
        b = a + srcDim;
        FOR_Y_COLUMN_IN_BOX(p, a, b)
        {
            size_t dstIdx = INDEX_BOX(GSMakeIntegerVector3(p.x+offsetX, p.y, p.z+offsetZ), nSunMinP, nSunMaxP);
            size_t srcIdx = INDEX_BOX(p, a, b);
            
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
                                             affectedAreaMinP:(vector_long3 * _Nullable)outAffectedAreaMinP
                                             affectedAreaMaxP:(vector_long3 * _Nullable)outAffectedAreaMaxP
{
    static const int blurSize = CHUNK_LIGHTING_MAX + 1;
    static const vector_long3 border = (vector_long3){1, 0, 1};
    
    vector_long3 p; // loop counter
    vector_long3 nSunMinP = GSCombinedMinP - border;
    vector_long3 nSunMaxP = GSCombinedMaxP + border;
    vector_long3 nSunDim = nSunMaxP - nSunMinP;
    
    size_t voxelCount = 0;
    GSVoxel *voxels = [self.voxelNeighborhood newVoxelBufferReturningCount:&voxelCount];
    
    // Populate the sunlight buffer with existing sunlight values from all the neighboring chunks.
    size_t nSunCount;
    GSTerrainBufferElement *sunlight = [self newSunlightBufferReturningCount:&nSunCount];

    // Clear sunlight values in the region affected by the edit.
    GSChunkSunlightData *center = [self neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    assert(center);
    vector_long3 editPosClp = GSCastToIntegerVector3(editPos - center.minP);

    vector_long3 workAreaMinP;
    workAreaMinP = editPosClp - GSMakeIntegerVector3(blurSize, 0, blurSize);
    workAreaMinP.y = 0;
    
    vector_long3 workAreaMaxP;
    workAreaMaxP = editPosClp + GSMakeIntegerVector3(blurSize, blurSize, blurSize);
    workAreaMaxP.y = MIN(workAreaMaxP.y, GSChunkSizeIntVec3.y);

    // If we're removing light then we need to zero out the blur region first.
    if (removingLight) {
        vector_long3 a = workAreaMinP + border, b = workAreaMaxP - border;
        FOR_BOX(p, a, b)
        {
            size_t srcIdx = INDEX_BOX(p, nSunMinP, nSunMaxP);
            assert(srcIdx < (nSunDim.x * nSunDim.y * nSunDim.z));
            sunlight[srcIdx] = 0;
        }
    }

    GSSunlightSeed(voxels, voxelCount,
                   GSCombinedMinP, GSCombinedMaxP,
                   sunlight, nSunCount,
                   nSunMinP, nSunMaxP,
                   workAreaMinP, workAreaMaxP);

    vector_long3 affectedMinP, affectedMaxP;
    GSSunlightBlur(voxels, voxelCount,
                   GSCombinedMinP, GSCombinedMaxP,
                   sunlight, nSunCount,
                   nSunMinP, nSunMaxP,
                   workAreaMinP, workAreaMaxP,
                   &affectedMinP, &affectedMaxP);
    
    // If sunlight was already in equilibrium state when we performed the sunlight blur then set the
    // affected area to a 3x3x3 cube surrounding the edit point. This will ensure geometry gets updated later.
    if((affectedMaxP.x <= affectedMinP.x) || (affectedMaxP.y <= affectedMinP.y) || (affectedMaxP.z <= affectedMinP.z)) {
        affectedMinP = editPosClp - GSMakeIntegerVector3(1, 1, 1);
        affectedMinP.y = MAX(affectedMinP.y, 0);
        
        affectedMaxP = editPosClp + GSMakeIntegerVector3(1, 1, 1);
        affectedMaxP.y = MIN(affectedMaxP.y, GSChunkSizeIntVec3.y);
    }

    if (outAffectedAreaMinP) {
        *outAffectedAreaMinP = affectedMinP;
    }

    if (outAffectedAreaMaxP) {
        *outAffectedAreaMaxP = affectedMaxP;
    }

    free(voxels);
    
    GSTerrainBuffer *result = [[GSTerrainBuffer alloc] initWithDimensions:nSunDim copyUnalignedData:sunlight];
    
    free(sunlight);
    
    return result;
}

@end
