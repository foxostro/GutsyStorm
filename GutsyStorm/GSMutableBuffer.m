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
    
    GSIntAABB selfBox = { GSZeroIntVec3, self.dimensions };
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(p.x >= selfBox.mins.x && p.x < selfBox.maxs.x &&
           p.y >= selfBox.mins.y && p.y < selfBox.maxs.y &&
           p.z >= selfBox.mins.z && p.z < selfBox.maxs.z);

    return &_data[INDEX_BOX(p, selfBox)];
}

@end
