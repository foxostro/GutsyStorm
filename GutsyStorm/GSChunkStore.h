//
//  GSChunkStore.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSRay.h"

@class GSCamera;
@class GSShader;
@class GSTerrainJournal;

@interface GSChunkStore : NSObject

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                                 camera:(nonnull GSCamera *)camera
                          terrainShader:(nonnull GSShader *)terrainShader
                              glContext:(nonnull NSOpenGLContext *)glContext
                              generator:(nonnull GSTerrainProcessorBlock)generator;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)drawActiveChunks;

- (void)updateWithCameraModifiedFlags:(unsigned)cameraModifiedFlags;

/* Enumerates the voxels on the specified ray up to the specified maximum depth. Calls the block for each voxel cell.
 * The block may set '*stop=YES;' to indicate that enumeration should terminate with a successful condition. The block
 * may set '*fail=YES;' to indicate that enumeration should terminate with a non-successful condition. Typically, this
 * occurs when the block realizes that it must block to take a lock.
 * Returns YES or NO depending on whether the operation was successful. This method will do its best to avoid blocking
 * (i.e. by waiting to take locks) and will return early if the alternative is to block. In this case, the function
 * returns NO.
 */
- (BOOL)enumerateVoxelsOnRay:(GSRay)ray
                    maxDepth:(unsigned)maxDepth
                   withBlock:(void (^ _Nonnull)(vector_float3 p, BOOL * _Nullable stop, BOOL * _Nullable fail))block;

/* Try to get the voxel at the specified position. If successful then store it in 'voxel' and return YES. If
 * unsuccessful then this returns NO without modifying the voxel pointed to by 'voxel'. This method may fail in this way
 * when it would have to block to take a lock.
 */
- (BOOL)tryToGetVoxelAtPoint:(vector_float3)pos voxel:(nonnull GSVoxel *)voxel;

- (GSVoxel)voxelAtPoint:(vector_float3)pos;

- (GSTerrainBufferElement)sunlightAtPoint:(vector_float3)pos;

- (void)placeBlockAtPoint:(vector_float3)pos
                    block:(GSVoxel)block
                  journal:(nullable GSTerrainJournal *)journal;

/* Notify the chunk store object that the system has come under memory pressure. */
- (void)memoryPressure:(dispatch_source_memorypressure_flags_t)status;

- (void)printInfo;

/* Clean-up in preparation for destroying the terrain object.
 * For example, synchronize with the disk one last time and resources.
 */
- (void)shutdown;

@end
