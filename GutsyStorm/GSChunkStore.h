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
#import "GSActiveRegion.h"


@interface GSChunkStore : NSObject
{
    NSLock *lockVoxelDataCache;
    NSCache *cacheVoxelData;
    
    NSLock *lockGeometryDataCache;
    NSCache *cacheGeometryData;
    
    dispatch_group_t groupForSaving;
    dispatch_queue_t chunkTaskQueue;
    
    NSLock *lock;
    NSUInteger numVBOGenerationsAllowedPerFrame;
    float terrainHeight;
    unsigned seed;
    GSCamera *camera;
    chunk_id_t oldCenterChunkID;
    NSURL *folder;
    GSShader *terrainShader;
    NSOpenGLContext *glContext;

    GSActiveRegion *activeRegion;
    GSVector3 activeRegionExtent; // The active region is specified relative to the camera position.
}

- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
         glContext:(NSOpenGLContext *)_glContext;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)drawActiveChunks;

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags;

- (BOOL)positionOfBlockAlongRay:(GSRay)ray
                           maxDist:(float)maxDist
                 outDistanceBefore:(float *)outDistanceBefore
                  outDistanceAfter:(float *)outDistanceAfter;

- (voxel_t)voxelAtPoint:(GSVector3)pos;

- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)block;

- (void)waitForSaveToFinish;

@end
