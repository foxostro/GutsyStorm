//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GLKVector3Extra.h" // for GLKVector3_ArePrettyMuchEqual
#import "GSBoxedVector.h"


@interface GSBoxedVector ()

- (NSUInteger)computeHash;

@end


@implementation GSBoxedVector
{
    GLKVector3 _vector;
    NSUInteger _cachedHash;
}

+ (GSBoxedVector *)boxedVectorWithVector:(GLKVector3)vector
{
    return [[GSBoxedVector alloc] initWithVector:vector];
}

+ (GSBoxedVector *)boxedVectorWithIntegerVector:(GSIntegerVector3)vector
{
    return [[GSBoxedVector alloc] initWithIntegerVector:vector];
}

- (instancetype)initWithVector:(GLKVector3)v
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _vector = v;
        _cachedHash = [self computeHash];
    }
    
    return self;
}

- (instancetype)initWithIntegerVector:(GSIntegerVector3)v
{
    self = [super init];
    if (self) {
        _vector = GLKVector3Make(v.x, v.y, v.z);
        _cachedHash = [self computeHash];
    }
    
    return self;
}

- (GLKVector3)vectorValue
{
    return _vector;
}

- (GSIntegerVector3)integerVectorValue
{
    return GSIntegerVector3_Make(_vector.x, _vector.y, _vector.z);
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
    
    GLKVector3 vector2 = [otherVector vectorValue];
    
    return GLKVector3AllEqualToVector3(_vector, vector2);
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
    return GLKVector3Hash(_vector);
}

@end
