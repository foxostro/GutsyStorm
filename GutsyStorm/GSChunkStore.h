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
#import "GSGrid.h"


@interface GSChunkStore : NSObject
{
    GSGrid *gridVoxelData;
    GSGrid *gridGeometryData;
    
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
    int needsChunkVisibilityUpdate;
    
    float timeUntilNextPeriodicChunkUpdate;
    float timeBetweenPerioducChunkUpdates;
    int32_t activeRegionNeedsUpdate;
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

/* Enumerates the voxels on the specified ray up to the specified maximum depth. Calls the block for each voxel cell. The block
 * may set '*stop=YES;' to indicate that enumeration should terminate.
 */
- (void)enumerateVoxelsOnRay:(GSRay)ray maxDepth:(unsigned)maxDepth withBlock:(void (^)(GSVector3 p, BOOL *stop))block;

- (voxel_t)voxelAtPoint:(GSVector3)pos;

- (void)placeBlockAtPoint:(GSVector3)pos block:(voxel_t)block;

- (void)waitForSaveToFinish;

@end
