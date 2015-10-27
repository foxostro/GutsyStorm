//
//  FoxMutableBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "FoxMutableBuffer.h"

@implementation FoxMutableBuffer

+ (instancetype)newMutableBufferWithBuffer:(GSTerrainBuffer *)buffer
{
    assert(buffer);
    return [[FoxMutableBuffer alloc] initWithDimensions:buffer.dimensions data:buffer->_data];
}

- (instancetype)initWithDimensions:(vector_long3)dim
{
    if (self = [super initWithDimensions:dim]) {
        // initialize here
    }

    return self;
}

- (instancetype)initWithDimensions:(vector_long3)dim data:(const terrain_buffer_element_t *)data
{
    if (self = [super initWithDimensions:dim data:data]) {
        // initialize here
    }

    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    // Copies the underlying buffer to a new buffer.
    return [[FoxMutableBuffer allocWithZone:zone] initWithDimensions:self.dimensions data:_data];
}

- (terrain_buffer_element_t *)mutableData
{
    return _data;
}

- (terrain_buffer_element_t *)pointerToValueAtPosition:(vector_long3)chunkLocalPos
{
    assert(_data);

    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(p.x >= 0 && p.x < dim.x &&
           p.y >= 0 && p.y < dim.y &&
           p.z >= 0 && p.z < dim.z);
    return &_data[INDEX_INTO_LIGHTING_BUFFER(dim, p)];
}

@end
