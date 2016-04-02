//
//  GSBoxedVector.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "GSIntegerVector3.h"

@interface GSBoxedVector : NSObject <NSCopying>

+ (GSBoxedVector *)boxedVectorWithVector:(vector_float3)vector;
+ (GSBoxedVector *)boxedVectorWithIntegerVector:(vector_long3)vector;
- (instancetype)initWithVector:(vector_float3)vector;
- (instancetype)initWithIntegerVector:(vector_long3)vector;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVector:(GSBoxedVector *)vector;
- (NSUInteger)hash;
- (NSString *)toString;
- (vector_float3)vectorValue;
- (vector_long3)integerVectorValue;

@end