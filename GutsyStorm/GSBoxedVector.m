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

static const float EPS = 1e-5;


@interface GSBoxedVector ()

- (NSUInteger)computeHash;

@end


@implementation GSBoxedVector

+ (GSBoxedVector *)boxedVectorWithVector:(GLKVector3)vector
{
    return [[GSBoxedVector alloc] initWithVector:vector];
}

+ (GSBoxedVector *)boxedVectorWithIntegerVector:(GSIntegerVector3)vector
{
    return [[GSBoxedVector alloc] initWithIntegerVector:vector];
}

- (id)initWithVector:(GLKVector3)v
{
    self = [super init];
    if (self) {
        // Initialization code here.
        vector = v;
        cachedHash = [self computeHash];
    }
    
    return self;
}

- (id)initWithIntegerVector:(GSIntegerVector3)v
{
    self = [super init];
    if (self) {
        vector = GLKVector3Make(v.x, v.y, v.z);
        cachedHash = [self computeHash];
    }
    
    return self;
}

- (GLKVector3)vectorValue
{
    return vector;
}

- (GSIntegerVector3)integerVectorValue
{
    return GSIntegerVector3_Make(vector.x, vector.y, vector.z);
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
    
    return GLKVector3AllEqualToVector3(vector, vector2);
}

- (NSUInteger)hash
{
    return cachedHash;
}

- (NSString *)toString
{
    return [NSString stringWithFormat:@"%f_%f_%f", vector.x, vector.y, vector.z];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (NSUInteger)computeHash
{
    return GLKVector3Hash(vector);
}

@end
