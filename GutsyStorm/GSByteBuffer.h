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


typedef uint8_t buffer_element_t;


static inline size_t BUFFER_SIZE_IN_BYTES(GSIntegerVector3 dimensions)
{
    return dimensions.x * dimensions.y * dimensions.z * sizeof(buffer_element_t);
}


// Columns in the y-axis are contiguous in memory.
static inline size_t INDEX_INTO_LIGHTING_BUFFER(GSIntegerVector3 dimensions, GSIntegerVector3 p)
{
    return (p.x * dimensions.y * dimensions.z) + (p.z * dimensions.y) + (p.y);
}


/* Represents a three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSByteBuffer : NSObject <NSCopying>
{
@protected
    GSIntegerVector3 _offsetFromChunkLocalSpace;
    buffer_element_t *_data;
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

/* Creates a new buffer of dimensions (CHUNK_SIZE_X+2) x (CHUNK_SIZE_Y) x (CHUNK_SIZE_Z+2).
 * The contents of the new buffer are initialized from the specified larger, raw buffer. Non-overlapping portions are discarded.
 */
+ (id)newBufferFromLargerRawBuffer:(uint8_t *)srcBuf
                           srcMinP:(GSIntegerVector3)srcMinP
                           srcMaxP:(GSIntegerVector3)srcMaxP;

/* Initialize a buffer of the specified dimensions */
- (id)initWithDimensions:(GSIntegerVector3)dim;

/* Initialize a buffer of the specified dimensions. The specified backing data is copied into the internal buffer. */
- (id)initWithDimensions:(GSIntegerVector3)dim data:(const buffer_element_t *)data;

/* Returns the value for the specified point in chunk-local space.
 * Always returns 0 for points which have no corresponding mapping in the buffer.
 */
- (buffer_element_t)valueAtPosition:(GSIntegerVector3)chunkLocalP;

/* Given a specific vertex position in the chunk, and a normal for that vertex, get the contribution of the (lighting) buffer on
 * the vertex.
 *
 * vertexPosInWorldSpace -- Vertex position in world space.
 * normal -- Vertex normal
 * minP -- Minimum corner of the chunk. This is the offset between world-space and chunk-local-space.
 *
 * As the lighting buffer has no knowledge of the neighboring chunks, expect values on the border to be incorrect.
 */
- (buffer_element_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                               withNormal:(GSIntegerVector3)normal
                                     minP:(GLKVector3)minP;

/* Saves the buffer contents to file asynchronously on the specified dispatch */
- (void)saveToFile:(NSURL *)url
             queue:(dispatch_queue_t)queue
             group:(dispatch_group_t)group;

@end