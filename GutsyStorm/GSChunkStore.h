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


typedef id chunk_id_t;


@interface GSChunkStore : NSObject
{
    NSCache *cacheVoxelData;
    NSCache *cacheGeometryData;
    
    dispatch_group_t groupForSaving;
    dispatch_queue_t chunkTaskQueue;
    
    float terrainHeight;
    unsigned seed;
    GSCamera *camera;
    chunk_id_t oldCenterChunkID;
    NSURL *folder;
    GSShader *terrainShader;
    GSActiveRegion *activeRegion;
    NSOpenGLContext *glContext;
    float timeBetweenPeriodicLightingUpdates;
    float timeUntilNextPeriodicLightingUpdate;
    
    NSLock *lock;
    
    int numVBOGenerationsAllowedPerFrame;
    int numVBOGenerationsRemaining;
}


- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
         glContext:(NSOpenGLContext *)_glContext;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)drawChunks;

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags;

- (BOOL)getPositionOfBlockAlongRay:(GSRay)ray
                           maxDist:(float)maxDist
                 outDistanceBefore:(float *)outDistanceBefore
                  outDistanceAfter:(float *)outDistanceAfter;

- (voxel_t)getVoxelAtPoint:(GSVector3)pos;

- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)block;

- (void)waitForSaveToFinish;

@end
