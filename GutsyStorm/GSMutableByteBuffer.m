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

- (id)initWithDimensions:(GSIntegerVector3)dim data:(const uint8_t *)data
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

- (id)copyWithZone:(NSZone *)zone
{
    return [[GSMutableByteBuffer allocWithZone:zone] initWithDimensions:self.dimensions data:_data];
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

- (void)tryToLoadFromFile:(NSURL *)url
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(BOOL success))completionHandler
{
    [GSByteBuffer newBufferFromFile:url
                         dimensions:self.dimensions
                              queue:queue
                  completionHandler:^(GSByteBuffer *aBuffer, NSError *error) {
                      if(aBuffer) {
                          assert(aBuffer->_data);
                          assert(aBuffer.dimensions == self.dimensions);

                          [_lockLightingBuffer lockForWriting];
                          assert(_data);
                          memcpy(_data, aBuffer->_data, BUFFER_SIZE_IN_BYTES);
                          completionHandler(YES);
                          [_lockLightingBuffer unlockForWriting];
                      } else {
                          completionHandler(NO);
                      }
                  }];
}

@end