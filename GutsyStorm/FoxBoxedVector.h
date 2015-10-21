//
//  FoxBoxedVector.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "FoxIntegerVector3.h"

@interface FoxBoxedVector : NSObject <NSCopying>

+ (FoxBoxedVector *)boxedVectorWithVector:(vector_float3)vector;
+ (FoxBoxedVector *)boxedVectorWithIntegerVector:(vector_long3)vector;
- (instancetype)initWithVector:(vector_float3)vector;
- (instancetype)initWithIntegerVector:(vector_long3)vector;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVector:(FoxBoxedVector *)vector;
- (NSUInteger)hash;
- (NSString *)toString;
- (vector_float3)vectorValue;
- (vector_long3)integerVectorValue;

@end