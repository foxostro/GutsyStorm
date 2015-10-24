//
//  FoxTextLabel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/21/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/matrix.h>

@interface FoxTextLabel : NSObject

@property (nonatomic, copy, setter=setText:) NSString * _Nonnull text;
@property (nonatomic, readwrite) matrix_float4x4 projectionMatrix;

- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)drawAtPoint:(NSPoint)point;

@end