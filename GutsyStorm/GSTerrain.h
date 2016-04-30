//
//  GSTerrain.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSChunkStore;
@class GSTerrainCursor;
@class GSTextureArray;
@class GSTerrainJournal;
@class GSChunkStore;

@interface GSTerrain : NSObject

@property (nonatomic, nonnull, readonly) GSTerrainJournal *journal;
@property (nonatomic, nonnull, readonly) GSChunkStore *chunkStore;

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                                 camera:(nonnull GSCamera *)cam
                              glContext:(nonnull NSOpenGLContext *)context;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)draw;

- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)cameraModifiedFlags;

- (void)placeBlockUnderCrosshairs;

- (void)removeBlockUnderCrosshairs;

/* Notify the terrain object that the system has come under memory pressure. */
- (void)memoryPressure:(dispatch_source_memorypressure_flags_t)status;

- (void)printInfo;

/* Clean-up in preparation for destroying the terrain object.
 * For example, synchronize with the disk one last time and resources.
 */
- (void)shutdown;

@end
