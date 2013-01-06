//
//  GSTerrain.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSChunkStore;
@class GSTerrainCursor;
@class GSTextureArray;

@interface GSTerrain : NSObject

- (id)initWithSeed:(NSUInteger)seed
            camera:(GSCamera *)camera
         glContext:(NSOpenGLContext *)glContext;

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
