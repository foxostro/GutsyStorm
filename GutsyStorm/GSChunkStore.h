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
#import "GSChunkGeometryData.h"
#import "GSCamera.h"
#import "GSShader.h"
#import "GSRenderTexture.h"


typedef id chunk_id_t;


@interface GSChunkStore : NSObject
{
    NSCache *cacheVoxelData;
    NSCache *cacheGeometryData;
    
    float terrainHeight;
    unsigned seed;
    GSCamera *camera;
    chunk_id_t oldCenterChunkID;
    NSURL *folder;
    GSShader *terrainShader;
    GSVector3 activeRegionExtent; // The active region is positioned relative to the camera.
    
    size_t maxActiveChunks;
    GSChunkGeometryData **activeChunks;
    
    // Limit the number of times chunk VBOs can be generated per frame.
    int numVBOGenerationsAllowedPerFrame;
    int numVBOGenerationsRemaining;
}

@property (readonly, nonatomic) GSVector3 activeRegionExtent;

+ (NSLock *)lockWhileLockingMultipleChunksVoxelData;
+ (NSLock *)lockWhileLockingMultipleChunksSunlight;

- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader;

- (void)drawChunks;

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags;

- (BOOL)getPositionOfBlockAlongRay:(GSRay)ray
                           maxDist:(float)maxDist
                 outDistanceBefore:(float *)outDistanceBefore
                  outDistanceAfter:(float *)outDistanceAfter;

- (voxel_t)getVoxelAtPoint:(GSVector3)pos;

- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)block;

@end
