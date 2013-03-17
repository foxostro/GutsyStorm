//
//  GSByteBuffer3D.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Voxel.h"
#import "GSReaderWriterLock.h"
#import "GSNeighborhood.h"

/* Represents a three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSMutableByteBuffer : NSObject

@property (readonly, nonatomic) uint8_t *data; // do not access without obtaining reader or writer access
@property (readonly, nonatomic) GSIntegerVector3 dimensions;

/* Initialize a buffer of the specified dimensions */
- (id)initWithDimensions:(GSIntegerVector3)dimensions;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (void)readerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (void)writerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryReaderAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryWriterAccessToBufferUsingBlock:(void (^)(void))block;

/* Returns the value for the specified point in chunk-local space.
 * The final value is interpolated from the values of adjacent cells in the buffer.
 * Always returns 0 for points which have no corresponding mapping in the buffer.
 * Assumes the caller is already holding the lock on the buffer.
 */
- (uint8_t)valueAtPoint:(GSIntegerVector3)chunkLocalP;

/* Given a specific vertex position in the chunk, and a normal for that vertex, get the contribution of the (lighting) buffer on
 * the vertex.
 *
 * vertexPosInWorldSpace -- Vertex position in world space.
 * normal -- Vertex normal
 * minP -- Minimum corner of the chunk. This is the offset between world-space and chunk-local-space.
 *
 * As the lighting buffer has no knowledge of the neighboring chunks, expect values on the border to be incorrect.
 * Assumes the caller is already holding the lock on the lighting buffer.
 */
- (uint8_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                      withNormal:(GSIntegerVector3)normal
                            minP:(GLKVector3)minP;

/* Clear the buffer to all zeroes.
 * Assumes the caller is already holding the buffer's lock for writing.
 */
- (void)clear;

/* Saves the buffer contents to file asynchronously on the specified dispatch 
 * Assumes the caller has already locked the lighting buffer for reading.
 */
- (void)saveToFile:(NSURL *)url queue:(dispatch_queue_t)queue group:(dispatch_group_t)group;

/* Attempts to asynchronously load the buffer contents from file on the specifed dispatch queue.
 * Runs the completion handler immediately after loading the file and does not run it if the file could not be loaded.
 */
- (void)tryToLoadFromFile:(NSURL *)url
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(BOOL success))completionHandler;

@end
