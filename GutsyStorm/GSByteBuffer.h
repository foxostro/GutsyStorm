//
//  GSByteBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKVector3.h>
#import "GSIntegerVector3.h"


#define BUFFER_SIZE_IN_BYTES (self.dimensions.x * self.dimensions.y * self.dimensions.z * sizeof(uint8_t))

// Columns in the y-axis are contiguous in memory.
#define INDEX_INTO_LIGHTING_BUFFER(p) ((size_t)(((p.x)*self.dimensions.y*self.dimensions.z) + ((p.z)*self.dimensions.y) + (p.y)))


/* Represents a three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSByteBuffer : NSObject <NSCopying>
{
@protected
    GSIntegerVector3 _offsetFromChunkLocalSpace;
    uint8_t *_data;
}

@property (readonly, nonatomic) GSIntegerVector3 dimensions;

/* Creates a new GSByteBuffer and initializes it with data from file.
 * The dimensions of the buffer must be specified upfront in order to ensure the file contains the correct amount of data.
 * File I/O is performed asynchronously on the specified queue, and the new object is returned through the completion handler block.
 * On error, the completion handler has aBuffer==nil and an error is provided with details.
 */
+ (void)newBufferFromFile:(NSURL *)url
               dimensions:(GSIntegerVector3)dimensions
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(GSByteBuffer *aBuffer, NSError *error))completionHandler;

/* Initialize a buffer of the specified dimensions */
- (id)initWithDimensions:(GSIntegerVector3)dim;

/* Initialize a buffer of the specified dimensions. The specified backing data is copied into the internal buffer. */
- (id)initWithDimensions:(GSIntegerVector3)dim data:(const uint8_t *)data;

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

/* Saves the buffer contents to file asynchronously on the specified dispatch
 * Assumes the caller has already locked the lighting buffer for reading.
 */
- (void)saveToFile:(NSURL *)url queue:(dispatch_queue_t)queue group:(dispatch_group_t)group;

@end