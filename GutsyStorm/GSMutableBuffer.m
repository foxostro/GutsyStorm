//
//  GSMutableBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSMutableBuffer.h"

@implementation GSMutableBuffer

+ (id)newMutableBufferWithBuffer:(GSBuffer *)buffer
{
    assert(buffer);
    return [[GSMutableBuffer alloc] initWithDimensions:buffer.dimensions data:buffer->_data];
}

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    if (self = [super initWithDimensions:dim]) {
        // initialize here
    }

    return self;
}

- (id)initWithDimensions:(GSIntegerVector3)dim data:(const buffer_element_t *)data
{
    if (self = [super initWithDimensions:dim data:data]) {
        // initialize here
    }

    return self;
}

- (buffer_element_t *)mutableData
{
    return _data;
}

- (buffer_element_t *)pointerToValueAtPosition:(GSIntegerVector3)chunkLocalPos
{
    assert(_data);

    GSIntegerVector3 dim = self.dimensions;
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);

    assert(p.x >= 0 && p.x < dim.x &&
           p.y >= 0 && p.y < dim.y &&
           p.z >= 0 && p.z < dim.z);
    return &_data[INDEX_INTO_LIGHTING_BUFFER(dim, p)];
}

@end
