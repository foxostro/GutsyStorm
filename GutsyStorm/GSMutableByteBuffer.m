//
//  GSLightingBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "Voxel.h"
#import "GSMutableByteBuffer.h"
#import "GSChunkVoxelData.h"
#import "SyscallWrappers.h"


@implementation GSMutableByteBuffer
{
    GSReaderWriterLock *_lockLightingBuffer;
}

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    self = [super initWithDimensions:dim];
    if (self) {
        _lockLightingBuffer = [[GSReaderWriterLock alloc] init];
    }

    return self;
}

- (id)initWithDimensions:(GSIntegerVector3)dim data:(uint8_t *)data
{
    self = [super initWithDimensions:dim data:data];
    if (self) {
        _lockLightingBuffer = [[GSReaderWriterLock alloc] init];
    }

    return self;
}

- (id)init
{
    return [self initWithDimensions:chunkSize];
}

- (uint8_t *)data
{
    return _data;
}

- (void)readerAccessToBufferUsingBlock:(void (^)(void))block
{
    [_lockLightingBuffer lockForReading];
    block();
    [_lockLightingBuffer unlockForReading];
}

- (void)writerAccessToBufferUsingBlock:(void (^)(void))block
{
    [_lockLightingBuffer lockForWriting];
    block();
    [_lockLightingBuffer unlockForWriting];
}

- (BOOL)tryReaderAccessToBufferUsingBlock:(void (^)(void))block
{
    if([_lockLightingBuffer tryLockForReading]) {
        block();
        [_lockLightingBuffer unlockForReading];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)tryWriterAccessToBufferUsingBlock:(void (^)(void))block
{
    if([_lockLightingBuffer tryLockForWriting]) {
        block();
        [_lockLightingBuffer unlockForWriting];
        return YES;
    } else {
        return NO;
    }
}

// Assumes the caller has already locked the lighting buffer for reading.
- (void)saveToFile:(NSURL *)url queue:(dispatch_queue_t)queue group:(dispatch_group_t)group
{
    dispatch_group_enter(group);

    dispatch_data_t sunlight = dispatch_data_create(self.data, BUFFER_SIZE_IN_BYTES,
                                                    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                    DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    dispatch_async(queue, ^{
        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

        dispatch_write(fd, sunlight, queue, ^(dispatch_data_t data, int error) {
            Close(fd);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_release(sunlight);
            dispatch_group_leave(group);
        });
    });
}

- (void)tryToLoadFromFile:(NSURL *)url
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(BOOL success))completionHandler
{
    [_lockLightingBuffer lockForWriting];

    // If the file does not exist then do nothing.
    if([url checkResourceIsReachableAndReturnError:NULL]) {
        int fd = Open(url, O_RDONLY, 0);
        dispatch_read(fd, BUFFER_SIZE_IN_BYTES, queue, ^(dispatch_data_t data, int error) {
            Close(fd);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with read(fd=%u)", fd]);
            }

            if(dispatch_data_get_size(data) != BUFFER_SIZE_IN_BYTES) {
                [NSException raise:@"data error"
                            format:@"Read %zu bytes from file, but expected %zu.",
                                        dispatch_data_get_size(data), BUFFER_SIZE_IN_BYTES];
            }

            // Map the data object to a buffer in memory and copy to our internal lighting buffer.
            size_t size = 0;
            const void *buffer = NULL;
            dispatch_data_t mappedData = dispatch_data_create_map(data, &buffer, &size);
            assert(BUFFER_SIZE_IN_BYTES == size);
            memcpy(_data, buffer, BUFFER_SIZE_IN_BYTES);
            dispatch_release(mappedData);

            completionHandler(YES);
            [_lockLightingBuffer unlockForWriting];
        });
    } else {
        completionHandler(NO);
        [_lockLightingBuffer unlockForWriting];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[GSMutableByteBuffer allocWithZone:zone] initWithDimensions:self.dimensions data:_data];
}

@end