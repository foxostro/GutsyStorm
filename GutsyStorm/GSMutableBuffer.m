//
//  GSMutableBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSMutableBuffer.h"
#import "GSBox.h"


@implementation GSMutableBuffer

+ (nonnull instancetype)newMutableBufferWithBuffer:(nonnull GSTerrainBuffer *)buffer
{
    NSParameterAssert(buffer);
    return [[[self class] alloc] initWithDimensions:buffer.dimensions cloneAlignedData:buffer->_data];
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    // Copies the underlying buffer to a new buffer.
    return [[[self class] allocWithZone:zone] initWithDimensions:self.dimensions cloneAlignedData:_data];
}

- (nonnull GSTerrainBufferElement *)mutableData
{
    return _data;
}

- (nonnull GSTerrainBufferElement *)pointerToValueAtPosition:(vector_long3)chunkLocalPos
{
    NSParameterAssert(_data);

    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(p.x >= 0 && p.x < dim.x &&
           p.y >= 0 && p.y < dim.y &&
           p.z >= 0 && p.z < dim.z);
    return &_data[INDEX_BOX(p, GSZeroIntVec3, dim)];
}

@end
