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


@interface GSChunkVoxelData : GSChunkData
{
    BOOL *voxelData;
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
- (BOOL)getVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z;
- (void)setVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z value:(BOOL)value;

@end
