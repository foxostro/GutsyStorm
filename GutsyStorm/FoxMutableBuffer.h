//
//  FoxMutableBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSTerrainBuffer.h"

@interface FoxMutableBuffer : GSTerrainBuffer

+ (nullable instancetype)newMutableBufferWithBuffer:(nonnull GSTerrainBuffer *)buffer;

- (nonnull terrain_buffer_element_t *)mutableData;

/* Returns a pointer to the value at the specified point in chunk-local space. */
- (nonnull terrain_buffer_element_t *)pointerToValueAtPosition:(vector_long3)chunkLocalPos;

@end
