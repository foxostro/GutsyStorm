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


typedef struct
{
	BOOL empty;   // YES, if the voxel is never drawn.
	BOOL outside; // YES, if the voxel is exposed to the sky from directly above.
} voxel_t;


@interface GSChunkVoxelData : GSChunkData
{
 @public
    voxel_t *voxelData;
	NSConditionLock *lockVoxelData;
}

+ (NSString *)fileNameFromMinP:(GSVector3)minP;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)chunkLocalP;
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)chunkLocalP;

@end
