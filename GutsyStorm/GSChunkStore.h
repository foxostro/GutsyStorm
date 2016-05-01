//
//  GSChunkStore.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSTerrainBuffer.h"


@class GSCamera;
@class GSShader;
@class GSTerrainJournal;
@class GSChunkVAO;
@class GSBoxedVector;
@class GSTerrainGenerator;


@interface GSChunkStore : NSObject

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                                 camera:(nonnull GSCamera *)camera
                          terrainShader:(nonnull GSShader *)terrainShader
                              glContext:(nonnull NSOpenGLContext *)glContext
                              generator:(nonnull GSTerrainGenerator *)generator;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)drawActiveChunks;

- (void)updateWithCameraModifiedFlags:(unsigned)cameraModifiedFlags;

/* Try to get the Vertex Array Object for the specified point in space.
 * Returns nil when it's not possible to get the VAO without blocking on a lock.
 */
- (nullable GSChunkVAO *)tryToGetVaoAtPoint:(vector_float3)pos;

/* Try to get the Vertex Array Object for the specified point in space.
 * Returns nil when it's not possible to get the VAO without blocking on a lock.
 * If the `createIfMissing' flag is set then the VAO is created if the slot was empty. This can take time.
 */
- (nullable GSChunkVAO *)nonBlockingVaoAtPoint:(nonnull GSBoxedVector *)p createIfMissing:(BOOL)createIfMissing;

/* Try to get the voxel at the specified position. If successful then store it in 'voxel' and return YES. If
 * unsuccessful then this returns NO without modifying the voxel pointed to by 'voxel'. This method may fail in this way
 * when it would have to block to take a lock.
 */
- (BOOL)tryToGetVoxelAtPoint:(vector_float3)pos voxel:(nonnull GSVoxel *)voxel;

- (GSVoxel)voxelAtPoint:(vector_float3)pos;

- (void)placeBlockAtPoint:(vector_float3)pos block:(GSVoxel)block addToJournal:(BOOL)addToJournal;

/* Notify the chunk store object that the system has come under memory pressure. */
- (void)memoryPressure:(dispatch_source_memorypressure_flags_t)status;

- (void)printInfo;

/* Clean-up in preparation for destroying the terrain object.
 * For example, synchronize with the disk one last time and resources.
 */
- (void)shutdown;

@end
