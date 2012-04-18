//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSChunkData.h"
#import "GSRay.h"


#define CONDITION_VOXEL_DATA_READY (1)


typedef struct
{
	BOOL empty;   // YES, if the voxel is never drawn.
	BOOL outside; // YES, if the voxel is exposed to the sky from directly above.
	unsigned sunlight; // Lighting for the voxel which is derived from exposure to the sun.
} voxel_t;


@interface GSChunkVoxelData : GSChunkData
{
    voxel_t *voxelData;
	NSConditionLock *lockVoxelData;
}

@property (readonly, nonatomic) NSConditionLock *lockVoxelData;

+ (NSString *)computeChunkFileNameWithMinP:(GSVector3)minP;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder;
- (void)saveToFileWithContainingFolder:(NSURL *)folder;
- (void)loadFromFile:(NSURL *)url;
- (BOOL)rayHitsChunk:(GSRay)ray intersectionDistanceOut:(float *)intersectionDistanceOut;

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z;
- (voxel_t *)getPointerToVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z;

@end
