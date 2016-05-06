//
//  GSVoxelNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSVoxelNeighborhood.h"
#import "GSSunlightUtils.h"

@implementation GSVoxelNeighborhood

- (nonnull GSChunkVoxelData *)neighborVoxelAtPoint:(nonnull vector_long3 *)chunkLocalP
{
    if(chunkLocalP->x >= CHUNK_SIZE_X) {
        chunkLocalP->x -= CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_ZER_Z];
        }
    } else if(chunkLocalP->x < 0) {
        chunkLocalP->x += CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_ZER_Z];
        }
    } else {
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_ZER_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_ZER_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
        }
    }
}

- (GSVoxel)voxelAtPoint:(vector_long3)p
{
    /* NOTE:
     *   - The voxels used for above/below the world must be updated when voxel def changes
     *   - Assumes each chunk spans the entire vertical extent of the world.
     */
    
    if(p.y < 0) {
        // Space below the world is always made of solid cubes.
        return (GSVoxel){.outside=NO,
            .exposedToAirOnTop=NO,
            .opaque=YES,
            .upsideDown=NO,
            .dir=VOXEL_DIR_NORTH,
            .type=VOXEL_TYPE_CUBE,
            .tex=VOXEL_TEX_DIRT};
    } else if(p.y >= CHUNK_SIZE_Y) {
        // Space above the world is always empty.
        return (GSVoxel){.outside=YES,
            .exposedToAirOnTop=YES,
            .opaque=NO,
            .upsideDown=NO,
            .dir=VOXEL_DIR_NORTH,
            .type=VOXEL_TYPE_EMPTY,
            .tex=0};
    } else {
        return [[self neighborVoxelAtPoint:&p] voxelAtLocalPosition:p];
    }
}

- (nonnull GSVoxel *)newVoxelBufferReturningCount:(size_t *)outCount
{
    static const size_t count = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    GSVoxel *combinedVoxelData = malloc(count*sizeof(GSVoxel));
    if(!combinedVoxelData) {
        [NSException raise:NSMallocException format:@"Failed to allocate memory for combinedVoxelData."];
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
        GSChunkVoxelData *neighbor = (GSChunkVoxelData *)[self neighborAtIndex:i];
        const GSVoxel *data = (const GSVoxel *)[neighbor.voxels data];
        long offsetX = offsetsX[i];
        long offsetZ = offsetsZ[i];
        
        vector_long3 p;
        FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
        {
            assert(p.x >= 0 && p.x < GSChunkSizeIntVec3.x);
            assert(p.y >= 0 && p.y < GSChunkSizeIntVec3.y);
            assert(p.z >= 0 && p.z < GSChunkSizeIntVec3.z);
            
            size_t dstIdx = INDEX_BOX(GSMakeIntegerVector3(p.x+offsetX, p.y, p.z+offsetZ), GSCombinedMinP, GSCombinedMaxP);
            size_t srcIdx = INDEX_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3);
            
            assert(dstIdx < count);
            assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));
            assert(sizeof(combinedVoxelData[0]) == sizeof(data[0]));
            
            memcpy(&combinedVoxelData[dstIdx], &data[srcIdx], CHUNK_SIZE_Y*sizeof(combinedVoxelData[0]));
        }
    }
    
    if (count) {
        *outCount = count;
    }
    
    return combinedVoxelData;
}

/* Generate and return sunlight data for the entire voxel neighborhood. */
- (nonnull GSTerrainBuffer *)newSunlightBuffer
{
    vector_long3 border = GSMakeIntegerVector3(CHUNK_LIGHTING_MAX+1, 0, CHUNK_LIGHTING_MAX+1);
    vector_long3 nSunMinP = GSZeroIntVec3 - border;
    vector_long3 nSunMaxP = GSChunkSizeIntVec3 + border;
    vector_long3 nSunDim = nSunMaxP - nSunMinP;
    
    assert(nSunMinP.x >= GSCombinedMinP.x &&
           nSunMinP.y >= GSCombinedMinP.y &&
           nSunMinP.z >= GSCombinedMinP.z);
    
    assert(nSunMaxP.x <= GSCombinedMaxP.x &&
           nSunMaxP.y <= GSCombinedMaxP.y &&
           nSunMaxP.z <= GSCombinedMaxP.z);
    
    size_t voxelCount = 0;
    GSVoxel *voxels = [self newVoxelBufferReturningCount:&voxelCount];
    
    size_t nSunCount = nSunDim.x * nSunDim.y * nSunDim.z;
    size_t nSunLen = nSunCount * sizeof(GSTerrainBufferElement);
    GSTerrainBufferElement *sunlight = [GSTerrainBuffer allocateBufferWithLength:nSunLen];
    bzero(sunlight, nSunLen); // Initially, set every element in the buffer to zero.
    
    GSSunlightSeed(voxels, voxelCount,
                   GSCombinedMinP, GSCombinedMaxP,
                   sunlight, nSunCount,
                   nSunMinP, nSunMaxP,
                   nSunMinP, nSunMaxP);
    
    // Every block above the elevation of the highest opaque block will be fully and directly lit.
    // We can take advantage of this to avoid a lot of work.
    vector_long3 maxBoxPoint = nSunMaxP;
    maxBoxPoint.y = GSFindElevationOfHighestOpaqueBlock(voxels, voxelCount, GSCombinedMinP, GSCombinedMaxP);
    
    GSSunlightBlur(voxels, voxelCount,
                   GSCombinedMinP, GSCombinedMaxP,
                   sunlight, nSunCount,
                   nSunMinP, nSunMaxP,
                   nSunMinP, maxBoxPoint,
                   NULL, NULL);
    
    free(voxels);
    
    GSTerrainBuffer *neighborhoodSunlight = [[GSTerrainBuffer alloc] initWithDimensions:nSunDim
                                                             takeOwnershipOfAlignedData:sunlight];
    
    vector_long3 a = -GSMakeIntegerVector3(1, 0, 1);
    vector_long3 b = GSMakeIntegerVector3(1, 0, 1) + GSChunkSizeIntVec3;
    GSTerrainBuffer *centerChunkSunlight = [neighborhoodSunlight copySubBufferWithMinCorner:a maxCorner:b];
    
    return centerChunkSunlight;
}

@end
