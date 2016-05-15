//
//  GSTerrainBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSBox.h"
#import "GSVoxel.h" // for GSVoxelBitwiseOp


typedef uint16_t GSTerrainBufferElement;


static inline size_t BUFFER_SIZE_IN_BYTES(vector_long3 dimensions)
{
    return dimensions.x * dimensions.y * dimensions.z * sizeof(GSTerrainBufferElement);
}


/* Represents a three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSTerrainBuffer : NSObject <NSCopying>
{
@protected
    vector_long3 _offsetFromChunkLocalSpace;
    GSTerrainBufferElement *_data;
}

/* Allocate a chunk of memory of size `len' bytes in length for use as a terrain element buffer.
 * `len' is the length of the buffer in bytes, not the count of elements.
 * The contents of the buffer are undefined.
 * This function cannot fail.
 */
+ (nonnull GSTerrainBufferElement *)allocateBufferWithLength:(NSUInteger)len;

/* Allocate a chunk of memory of size `len' bytes in length for use as a terrain element buffer.
 * `len' is the length of the buffer in bytes, not the count of elements.
 * The contents of the buffer are identical to the specified `src' buffer, which must be a buffer allocated with
 * either bufferAllocate, bufferClone, or bufferCloneUnaligned.
 *
 * The retrictions on `src' permit a very fast and inexpensive copy.
 */
+ (nonnull GSTerrainBufferElement *)cloneBuffer:(nonnull const GSTerrainBufferElement *)src len:(NSUInteger)len;

/* Identical to bufferClone except that the restriction on `src' is relaxed and is permitted to be any memory.
 * `len' is the length of the buffer in bytes, not the count of elements.
 */
+ (nonnull GSTerrainBufferElement *)cloneUnalignedBuffer:(nonnull const GSTerrainBufferElement*)src len:(NSUInteger)len;

/* Deallocate a buffer previosuly created by bufferAllocate, bufferClone, or bufferCloneUnaligned.
 * `len' is the length of the buffer in bytes, not the count of elements.
 */
+ (void)deallocateBuffer:(nullable GSTerrainBufferElement *)buffer len:(NSUInteger)len;

@property (nonatomic, readonly) vector_long3 offsetFromChunkLocalSpace;
@property (nonatomic, readonly) vector_long3 dimensions;

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

/* Saves the buffer contents to file asynchronously on the specified dispatch queue abd group.
 * Sticks the header to the front of the file, if one is provided.
 */
- (void)saveToFile:(nonnull NSURL *)url
             queue:(nonnull dispatch_queue_t)queue
             group:(nonnull dispatch_group_t)group
            header:(nullable NSData *)header;

/* Creates a new buffer of dimensions of smaller dimensions than this buffer. */
- (nonnull instancetype)copySubBufferFromSubrange:(GSIntAABB * _Nonnull)srcBox;

/* Creates a new buffer with the contents of this buffer plus a modification applied as specified. */
- (nonnull instancetype)copyWithEditAtPosition:(vector_long3)chunkLocalPos
                                         value:(GSTerrainBufferElement)value
                                     operation:(GSVoxelBitwiseOp)op;

- (nonnull GSTerrainBufferElement *)data;

@end