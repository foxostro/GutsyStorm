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

@interface GSBoxedVector : NSObject <NSCopying, NSCoding>

+ (nonnull GSBoxedVector *)boxedVectorWithVector:(vector_float3)vector;
+ (nonnull GSBoxedVector *)boxedVectorWithIntegerVector:(vector_long3)vector;

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)decoder;
- (nonnull instancetype)initWithVector:(vector_float3)vector;
- (nonnull instancetype)initWithIntegerVector:(vector_long3)vector;
- (nonnull instancetype)initWithString:(nonnull NSString *)string;

- (BOOL)isEqual:(nullable id)other;
- (BOOL)isEqualToVector:(nullable GSBoxedVector *)vector;
- (NSUInteger)hash;
- (nonnull NSString *)toString;
- (vector_float3)vectorValue;
- (vector_long3)integerVectorValue;

@end