//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import "GSVectorUtils.h"
#import "GSBoxedVector.h"


@interface GSBoxedVector ()

- (NSUInteger)computeHash;

@end


@implementation GSBoxedVector
{
    vector_float3 _vector;
    NSUInteger _cachedHash;
}

+ (GSBoxedVector *)boxedVectorWithVector:(vector_float3)vector
{
    return [[GSBoxedVector alloc] initWithVector:vector];
}

+ (GSBoxedVector *)boxedVectorWithIntegerVector:(vector_long3)vector
{
    return [[GSBoxedVector alloc] initWithIntegerVector:vector];
}

- (instancetype)initWithVector:(vector_float3)v
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _vector = v;
        _cachedHash = [self computeHash];
    }
    
    return self;
}

- (instancetype)initWithIntegerVector:(vector_long3)v
{
    self = [super init];
    if (self) {
        _vector = (vector_float3){v.x, v.y, v.z};
        _cachedHash = [self computeHash];
    }
    
    return self;
}

- (vector_float3)vectorValue
{
    return _vector;
}

- (vector_long3)integerVectorValue
{
    return GSMakeIntegerVector3(_vector.x, _vector.y, _vector.z);
}

- (BOOL)isEqual:(id)other
{
    if(other == self) {
        return YES;
    }
    
    if(!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    
    return [self isEqualToVector:other];
}

- (BOOL)isEqualToVector:(GSBoxedVector *)otherVector
{
    if(self == otherVector) {
        return YES;
    }

    vector_float3 vector2 = [otherVector vectorValue];

    return (_vector.x == vector2.x) && (_vector.y == vector2.y) && (_vector.z == vector2.z);
}

- (NSUInteger)hash
{
    return _cachedHash;
}

- (NSString *)toString
{
    return [NSString stringWithFormat:@"%f_%f_%f", _vector.x, _vector.y, _vector.z];
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // GSBoxedVector is immutable. Return self rather than performing a deep copy.
}

- (NSUInteger)computeHash
{
    return vector_hash(_vector);
}

@end
