//
//  GSByteBuffer3D.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSByteBuffer.h"

/* Represents a mutable three-dimensional grid of bytes.
 * This can be used for myriad purposes including volumetric lighting values and voxel data.
 */
@interface GSMutableByteBuffer : GSByteBuffer

/* Initialize a buffer of the specified dimensions */
- (id)initWithDimensions:(GSIntegerVector3)dimensions;

/* Initialize a buffer of the specified dimensions. The specified backing data is copied into the internal buffer. */
- (id)initWithDimensions:(GSIntegerVector3)dim data:(const buffer_element_t *)data;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (void)readerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (void)writerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryReaderAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryWriterAccessToBufferUsingBlock:(void (^)(void))block;

/* Copies the contents of the specified buffer into this buffer. Assumes the caller has already locked the buffer for writing. */
- (void)setContents:(GSByteBuffer *)src;

/* Attempts to asynchronously load the buffer contents from file on the specifed dispatch queue.
 * Runs the completion handler immediately after loading the file and does not run it if the file could not be loaded.
 */
- (void)tryToLoadFromFile:(NSURL *)url
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(BOOL success))completionHandler;

@end
