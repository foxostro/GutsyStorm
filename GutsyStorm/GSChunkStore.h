//
//  GSChunkStore.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSRay.h"

@class GSCamera;
@class GSShader;

@interface GSChunkStore : NSObject

- (instancetype)initWithSeed:(NSUInteger)seed
                      camera:(GSCamera *)camera
               terrainShader:(GSShader *)terrainShader
                   glContext:(NSOpenGLContext *)glContext
                   generator:(terrain_generator_t)generator
               postProcessor:(terrain_post_processor_t)postProcessor;

/* Assumes the caller has already locked the GL context or
 * otherwise ensures no concurrent GL calls will be made.
 */
- (void)drawActiveChunks;

- (void)updateWithCameraModifiedFlags:(unsigned)cameraModifiedFlags;

/* Enumerates the voxels on the specified ray up to the specified maximum depth. Calls the block for each voxel cell. The block
 * may set '*stop=YES;' to indicate that enumeration should terminate with a successful condition. The block may set '*fail=YES;'
 * to indicate that enumeration should terminate with a non-successful condition. Typically, this occurs when the block realizes
 * that it must block to take a lock.
 * Returns YES or NO depending on whether the operation was successful. This method will do its best to avoid blocking (i.e. by
 * waiting to take locks) and will return early if the alternative is to block. In this case, the function returns NO.
 */
- (BOOL)enumerateVoxelsOnRay:(GSRay)ray maxDepth:(unsigned)maxDepth withBlock:(void (^)(GLKVector3 p, BOOL *stop, BOOL *fail))block;

/* Try to get the voxel at the specified position. If successful then store it in 'voxel' and return YES. If unsuccessful then
 * this returns NO without modifying the voxel pointed to by 'voxel'. This method may fail in this way when it would have to block
 * to take a lock.
 */
- (BOOL)tryToGetVoxelAtPoint:(GLKVector3)pos voxel:(voxel_t *)voxel;

- (voxel_t)voxelAtPoint:(GLKVector3)pos;

- (void)placeBlockAtPoint:(GLKVector3)pos block:(voxel_t)block;

- (void)purge;

/* Clean-up in preparation for destroying the terrain object.
 * For example, synchronize with the disk one last time and resources.
 */
- (void)shutdown;

@end
