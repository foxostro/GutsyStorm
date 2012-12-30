//
//  GSLightingBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSReaderWriterLock.h"
#import "GSNeighborhood.h"
#import "Voxel.h"

@class GSChunkVoxelData;

// A chunk-sized buffer of lighting values. For example, the lighting contribution, per block, of direct sunlight.
@interface GSLightingBuffer : NSObject
{
 @public
    GSReaderWriterLock *lockLightingBuffer;
    uint8_t *lightingBuffer;
    GSIntegerVector3 dimensions;
    GSIntegerVector3 offsetFromChunkLocalSpace;
}

@property (readonly, nonatomic) GSReaderWriterLock *lockLightingBuffer;
@property (readonly, nonatomic) uint8_t *lightingBuffer;
@property (readonly, nonatomic) GSIntegerVector3 dimensions;

/* Initialize a lighting buffer of the specified dimensions */
- (id)initWithDimensions:(GSIntegerVector3)dimensions;

/* Obtains a reader lock on the the lighting buffer and allows the caller to access it in the specified block. */
- (void)readerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the lighting buffer and allows the caller to access it in the specified block. */
- (void)writerAccessToBufferUsingBlock:(void (^)(void))block;

/* Returns the light value for the specified point in chunk-local space.
 * Always returns 0 for points which have no corresponding mapping in the lighting buffer.
 * Assumes the caller is already holding the lock on the lighting buffer.
 */
- (uint8_t)lightAtPoint:(GSIntegerVector3)chunkLocalP;

/* Given a specific vertex position in the chunk, and a normal for that vertex, get the contribution of the lighting buffer on
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

/* Clear the lighting buffer to all zeroes.
 * Assumes the caller is already holding the buffer's lock for writing.
 */
- (void)clear;

/* Saves the lighting buffer contents to file. */
- (void)saveToFile:(NSURL *)url;

/* Attempts to load the lighting buffer contents from file.
 * Returns YES if the file was actually loaded.
 * Runs the completion handler immediately after loading the file and does not run it if the file could not be loaded.
 */
- (BOOL)tryToLoadFromFile:(NSURL *)url completionHandler:(void (^)(void))completionHandler;

@end
