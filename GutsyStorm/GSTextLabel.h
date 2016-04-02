//
//  GSTextLabel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/21/15.
//  Copyright © 2015-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/matrix.h>

@interface GSTextLabel : NSObject

@property (nonatomic, copy, nonnull, setter=setText:) NSString *text;
@property (nonatomic, readwrite) matrix_float4x4 projectionMatrix;

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)drawAtPoint:(NSPoint)point;

@end
