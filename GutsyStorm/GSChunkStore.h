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
#import "GSChunk.h"
#import "GSCube.h"
#import "GSCamera.h"
#import "GSShader.h"
#import "GSRenderTexture.h"

#define NUM_BG_SUB_REGIONS (3)


@interface GSChunkStore : NSObject
{
    NSCache *cache;
    float terrainHeight;
    unsigned seed;
    GSCamera *camera;
	NSString *oldCenterChunkID;
	NSURL *folder;
    GSShader *terrainShader;
    GSVector3 activeRegionExtent; // The active region is positioned relative to the camera.
	
	size_t maxActiveChunks;
    GSChunk **activeChunks;
    
	NSMutableArray *feelerRays;
	
	// Limit the number of times chunk VBOs can be generated per frame.
	int numVBOGenerationsAllowedPerFrame;
	int numVBOGenerationsRemaining;
    
    GSCube *skybox;
    GSShader *skyboxShader;
    GSCamera *skyboxCamera[6]; // cameras for rendering the skybox
    GSRenderTexture *skyboxCubemap[NUM_BG_SUB_REGIONS];
	int skyboxUpdateCountdown[NUM_BG_SUB_REGIONS];
	int faceForNextUpdate[NUM_BG_SUB_REGIONS];
	BOOL faceIsDirty[NUM_BG_SUB_REGIONS * 6];
	
	// For LOD, the active region is broken up into a foreground sub-region and several background sub-regions.
	float foregroundRegionSize;
	float backgroundRegionInnerRadius[NUM_BG_SUB_REGIONS];
	float backgroundRegionOuterRadius[NUM_BG_SUB_REGIONS];
	int skyboxUpdateDelays[NUM_BG_SUB_REGIONS];
}

@property (readonly, nonatomic) GSVector3 activeRegionExtent;

- (id)initWithSeed:(unsigned)_seed camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
      skyboxShader:(GSShader *)_skyboxShader;
- (void)updateSkybox;
- (void)drawSkybox;
- (void)drawChunks;
- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)cameraModifiedFlags;
- (GSChunk *)getChunkAtPoint:(GSVector3)p;
- (GSChunk *)rayCastToFindChunk:(GSRay)ray intersectionDistanceOut:(float *)intersectionDistanceOut;

@end
