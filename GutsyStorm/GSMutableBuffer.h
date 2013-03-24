//
//  GSMutableBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/23/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSBuffer.h"

@interface GSMutableBuffer : GSBuffer

+ (id)newMutableBufferWithBuffer:(GSBuffer *)buffer;

- (buffer_element_t *)mutableData;

/* Returns a pointer to the value at the specified point in chunk-local space. */
- (buffer_element_t *)pointerToValueAtPosition:(GSIntegerVector3)chunkLocalPos;

@end
