//
//  GSChunkVoxelLightingData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/19/12.
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

#define CHUNK_LIGHTING_MAX (3)


@class GSChunkVoxelData;


@interface GSChunkVoxelLightingData : GSChunkData
{
 @public
	int *sunlight;
	NSConditionLock *lockLightingData;
}

+ (NSString *)fileNameFromMinP:(GSVector3)minP;

- (id)initWithChunkAndNeighbors:(GSChunkVoxelData **)chunks
						 folder:(NSURL *)folder;

// Assumes the caller is already holding "lockLightingData".
- (int)getSunlightAtPoint:(GSIntegerVector3)p assumeBlocksOutsideChunkAreDark:(BOOL)assumeBlocksOutsideChunkAreDark;

@end
