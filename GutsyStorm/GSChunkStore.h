//
//  GSChunkStore.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSVector3.h"
#import "GSRay.h"
#import "GSChunkVoxelData.h"
#import "GSChunkVoxelLightingData.h"
#import "GSChunkGeometryData.h"
#import "GSCamera.h"
#import "GSShader.h"
#import "GSRenderTexture.h"


@interface GSChunkStore : NSObject
{
    NSCache *cacheVoxelData;
    NSCache *cacheVoxelLightingData;
    NSCache *cacheGeometryData;
	
    float terrainHeight;
    unsigned seed;
    GSCamera *camera;
	NSString *oldCenterChunkID;
	NSURL *folder;
    GSShader *terrainShader;
    GSVector3 activeRegionExtent; // The active region is positioned relative to the camera.
	
	size_t maxActiveChunks;
    GSChunkGeometryData **activeChunks;
}

@property (readonly, nonatomic) GSVector3 activeRegionExtent;

+ (NSLock *)lockWhileLockingMultipleChunks;

- (id)initWithSeed:(unsigned)_seed
			camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader;

- (void)drawChunks;

- (void)updateWithDeltaTime:(float)dt
		cameraModifiedFlags:(unsigned)cameraModifiedFlags;

@end
