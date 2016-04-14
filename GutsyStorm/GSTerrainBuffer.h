//
//  GSTerrainBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSVoxel.h"


typedef uint16_t GSTerrainBufferElement;


static inline size_t BUFFER_SIZE_IN_BYTES(vector_long3 dimensions)
{
    return dimensions.x * dimensions.y * dimensions.z * sizeof(GSTerrainBufferElement);
}


// Columns in the y-axis are contiguous in memory.
static inline size_t INDEX_INTO_LIGHTING_BUFFER(vector_long3 dimensions, vector_long3 p)
{
    return (p.x * dimensions.y * dimensions.z) + (p.z * dimensions.y) + (p.y);
}


@class GSTerrainBuffer;


typedef void (^GSBufferCompletionHandler)(GSTerrainBuffer * _Nonnull aBuffer, NSError * _Nullable error);


/* Represents a three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSTerrainBuffer : NSObject <NSCopying>
{
@protected
    vector_long3 _offsetFromChunkLocalSpace;
    GSTerrainBufferElement *_data;
}

@property (nonatomic, readonly) vector_long3 dimensions;

/* Creates a new buffer of dimensions (CHUNK_SIZE_X+2) x (CHUNK_SIZE_Y) x (CHUNK_SIZE_Z+2).
 * The contents of the new buffer are initialized from the specified larger, raw buffer. Non-overlapping portions are
 * discarded.
 */
+ (nonnull instancetype)newBufferFromLargerRawBuffer:(const GSTerrainBufferElement * _Nonnull)srcBuf
                                             srcMinP:(vector_long3)srcMinP
                                             srcMaxP:(vector_long3)srcMaxP;

/* Initialize a buffer of the specified dimensions. Contents are undefined. */
- (nonnull instancetype)initWithDimensions:(vector_long3)dim;

/* Initialize a buffer of the specified dimensions.
 * Unlike other initializers, there are no restrictions on the memory pointed to by `data'.
 */
- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                         copyUnalignedData:(const GSTerrainBufferElement * _Nonnull)data;

/* Initialize a buffer of the specified dimensions.
 * The `data' pointer must point to appropriately allocated memory. This class takes direct ownership of that memory
 * including assuming responsibility for freeing it later.
 */
- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                takeOwnershipOfAlignedData:(GSTerrainBufferElement * _Nonnull)data;

/* Initialize a buffer of the specified dimensions. Buffer contents will be identical to the buffer at `data'.
 * The `data' pointer must point to appropriately allocated memory.
 */
- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                          cloneAlignedData:(const GSTerrainBufferElement * _Nonnull)data;

/* Returns the value for the specified point in chunk-local space.
 * Always returns 0 for points which have no corresponding mapping in the buffer.
 */
- (GSTerrainBufferElement)valueAtPosition:(vector_long3)chunkLocalP;

/* Given a specific vertex position in the chunk, and a normal for that vertex, get the contribution of the (lighting)
 * buffer on the vertex.
 *
 * vertexPosInWorldSpace -- Vertex position in world space.
 * normal -- Vertex normal
 * minP -- Minimum corner of the chunk. This is the offset between world-space and chunk-local-space.
 *
 * As the lighting buffer has no knowledge of the neighboring chunks, expect values on the border to be incorrect.
 */
- (GSTerrainBufferElement)lightForVertexAtPoint:(vector_float3)vertexPosInWorldSpace
                                     withNormal:(vector_long3)normal
                                           minP:(vector_float3)minP;

/* Saves the buffer contents to file asynchronously on the specified dispatch */
- (void)saveToFile:(nonnull NSURL *)url
             queue:(nonnull dispatch_queue_t)queue
             group:(nonnull dispatch_group_t)group;

/* Copies this buffer into a sub-range of another buffer of dimensions defined by GSCombinedMinP and GSCombinedMaxP. */
- (void)copyToCombinedNeighborhoodBuffer:(nonnull GSTerrainBufferElement *)dstBuf
                                   count:(NSUInteger)count
                                neighbor:(GSVoxelNeighborIndex)neighbor;

- (nonnull GSTerrainBuffer *)copyWithEditAtPosition:(vector_long3)chunkLocalPos value:(GSTerrainBufferElement)value;

- (nonnull GSTerrainBufferElement *)data;

@end