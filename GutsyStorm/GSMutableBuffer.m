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

@end
