//
//  GSMutableBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSMutableBuffer.h"

@implementation GSMutableBuffer

+ (nonnull instancetype)newMutableBufferWithBuffer:(nonnull GSTerrainBuffer *)buffer
{
    assert(buffer);
    return [[GSMutableBuffer alloc] initWithDimensions:buffer.dimensions data:buffer->_data];
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim
{
    if (self = [super initWithDimensions:dim]) {
        // initialize here
    }

    return self;
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim data:(nonnull const GSTerrainBufferElement *)data
{
    if (self = [super initWithDimensions:dim data:data]) {
        // initialize here
    }

    return self;
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    // Copies the underlying buffer to a new buffer.
    return [[GSMutableBuffer allocWithZone:zone] initWithDimensions:self.dimensions data:_data];
}

- (nonnull GSTerrainBufferElement *)mutableData
{
    return _data;
}

- (nonnull GSTerrainBufferElement *)pointerToValueAtPosition:(vector_long3)chunkLocalPos
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
