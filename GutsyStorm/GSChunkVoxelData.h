//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSChunkData.h"
#import "GSIntegerVector3.h"
#import "GSReaderWriterLock.h"


#define CHUNK_NEIGHBOR_POS_X_NEG_Z  (0)
#define CHUNK_NEIGHBOR_POS_X_ZER_Z  (1)
#define CHUNK_NEIGHBOR_POS_X_POS_Z  (2)
#define CHUNK_NEIGHBOR_NEG_X_NEG_Z  (3)
#define CHUNK_NEIGHBOR_NEG_X_ZER_Z  (4)
#define CHUNK_NEIGHBOR_NEG_X_POS_Z  (5)
#define CHUNK_NEIGHBOR_ZER_X_NEG_Z  (6)
#define CHUNK_NEIGHBOR_ZER_X_POS_Z  (7)
#define CHUNK_NEIGHBOR_CENTER       (8)
#define CHUNK_NUM_NEIGHBORS         (9)

#define CHUNK_LIGHTING_MAX (7)


#define VOXEL_EMPTY   (1) // a flag on the first LSB
#define VOXEL_OUTSIDE (2) // a flag on the second LSB

#define VOXEL_IS_EMPTY(flags)   ((flags) & VOXEL_EMPTY)
#define VOXEL_IS_OUTSIDE(flags) ((flags) & VOXEL_OUTSIDE)

typedef uint8_t voxel_t;


static inline uint8_t avgSunlight(float a, float b, float c, float d)
{
    // Average four sunlight values (each is between 0.0 and 1.0)
    float average = ((a+b+c+d)*0.25f);
    
    return (uint8_t)(average * 255.0f); // convert to integer between 0 and 255
}


static inline uint8_t calcFinalOcclusion(float a, float b, float c, float d)
{
    float occlusion = a+b+c+d;
    
    return (uint8_t)(occlusion * 255.0f); // convert to integer between 0 and 255
}


typedef struct
{
    /* Each face has four vertices, and we need a brightness factor for
     * all 24 of these vertices.
     */
    
    uint8_t top[4];
    uint8_t bottom[4];
    uint8_t left[4];
    uint8_t right[4];
    uint8_t front[4];
    uint8_t back[4];
} block_lighting_t;


@interface GSChunkVoxelData : GSChunkData
{
    NSURL *folder;
    BOOL dirty;
    dispatch_group_t groupForSaving;
    
 @public
    GSReaderWriterLock *lockVoxelData;
    voxel_t *voxelData;
    
    GSReaderWriterLock *lockSunlight;
    uint8_t *sunlight;
    
    NSConditionLock *lockAmbientOcclusion;
    block_lighting_t *ambientOcclusion;
}

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
     terrainHeight:(float)terrainHeight
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving;

- (void)updateLightingWithNeighbors:(GSChunkVoxelData **)neighbors doItSynchronously:(BOOL)sync;

- (void)markAsDirtyAndSpinOffSavingTask;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

// Assumes the caller is already holding "lockSunlight" on all neighbors and "lockVoxelData" on self, at least.
- (void)getSunlightAtPoint:(GSIntegerVector3)p
                 neighbors:(GSChunkVoxelData **)voxels
               outLighting:(block_lighting_t *)lighting;

// Assumes the caller is already holding "lockAmbientOcclusion".
- (block_lighting_t)getAmbientOcclusionAtPoint:(GSIntegerVector3)p;

@end


// Assumes the caller is already holding "lockVoxelData" on all chunks in neighbors.
GSChunkVoxelData* getNeighborVoxelAtPoint(GSIntegerVector3 chunkLocalP,
                                          GSChunkVoxelData **neighbors,
                                          GSIntegerVector3 *outRelativeToNeighborP);


// Assumes the caller is already holding "lockVoxelData" on all chunks in neighbors.
BOOL isEmptyAtPoint(GSIntegerVector3 p, GSChunkVoxelData **neighbors);


void fullBlockLighting(block_lighting_t *ao);

void freeNeighbors(GSChunkVoxelData **chunks);

GSChunkVoxelData ** copyNeighbors(GSChunkVoxelData **chunks);