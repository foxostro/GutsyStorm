//
//  GSTerrain.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSTextureArray.h"
#import "Voxel.h"
#import "GSChunkStore.h"
#import "GSTerrainCursor.h"

@interface GSTerrain : NSObject
{
    GSCamera *camera;
    GSTextureArray *textureArray;
    GSChunkStore *chunkStore;
    GSTerrainCursor *cursor;
    
    float maxPlaceDistance;
}

- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
         glContext:(NSOpenGLContext *)_glContext;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)draw;

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)cameraModifiedFlags;

- (void)sync;

- (void)placeBlockUnderCrosshairs;

- (void)removeBlockUnderCrosshairs;

@end
