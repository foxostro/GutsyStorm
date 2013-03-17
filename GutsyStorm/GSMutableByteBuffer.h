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
- (id)initWithDimensions:(GSIntegerVector3)dim data:(uint8_t *)data;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (void)readerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (void)writerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a reader lock on the the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryReaderAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the buffer and allows the caller to access it in the specified block. */
- (BOOL)tryWriterAccessToBufferUsingBlock:(void (^)(void))block;

/* Returns a raw pointer to the internal buffer. Do not access without obtaining the lock first. */
- (uint8_t *)data;

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
