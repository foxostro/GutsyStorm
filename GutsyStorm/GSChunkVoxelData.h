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


typedef struct
{
	BOOL empty;   // YES, if the voxel is never drawn.
	BOOL outside; // YES, if the voxel is exposed to the sky from directly above.
} voxel_t;


typedef struct
{
	// Each block has eigh vertices, this is the ambient occlusion factors for each one.
	float ftr;
	float ftl;
	float fbr;
	float fbl;
	float btr;
	float btl;
	float bbr;
	float bbl;
} ambient_occlusion_t;


@interface GSChunkVoxelData : GSChunkData
{
 @public
    NSConditionLock *lockVoxelData;
	voxel_t *voxelData;
	
	NSConditionLock *lockSunlight;
	int *sunlight;
	
	NSConditionLock *lockAmbientOcclusion;
	ambient_occlusion_t *ambientOcclusion;
}

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP;

+ (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3)chunkLocalP
									neighbors:(GSChunkVoxelData **)neighbors
					   outRelativeToNeighborP:(GSIntegerVector3 *)outRelativeToNeighborP;

+ (BOOL)isEmptyAtPoint:(GSIntegerVector3)p neighbors:(GSChunkVoxelData **)neighbors;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder;

- (void)updateLightingWithNeighbors:(GSChunkVoxelData **)neighbors;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

// Assumes the caller is already holding "lockSunlight".
- (int)getSunlightAtPoint:(GSIntegerVector3)p;

// Assumes the caller is already holding "lockAmbientOcclusion".
- (ambient_occlusion_t)getAmbientOcclusionAtPoint:(GSIntegerVector3)p;

@end
