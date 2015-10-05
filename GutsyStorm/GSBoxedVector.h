//
//  GSBoxedVector.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"

@interface GSBoxedVector : NSObject <NSCopying>

+ (GSBoxedVector *)boxedVectorWithVector:(GLKVector3)vector;
+ (GSBoxedVector *)boxedVectorWithIntegerVector:(GSIntegerVector3)vector;
- (instancetype)initWithVector:(GLKVector3)vector;
- (instancetype)initWithIntegerVector:(GSIntegerVector3)vector;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVector:(GSBoxedVector *)vector;
- (NSUInteger)hash;
- (NSString *)toString;
- (GLKVector3)vectorValue;
- (GSIntegerVector3)integerVectorValue;

@end
