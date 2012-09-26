//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSBoxedVector.h"

static const float EPS = 1e-5;


@interface GSBoxedVector (Private)

- (NSUInteger)computeHash;

@end


@implementation GSBoxedVector

+ (GSBoxedVector *)boxedVectorWithVector:(GSVector3)vector
{
    return [[[GSBoxedVector alloc] initWithVector:vector] autorelease];
}


+ (GSBoxedVector *)boxedVectorWithIntegerVector:(GSIntegerVector3)vector
{
    return [[[GSBoxedVector alloc] initWithIntegerVector:vector] autorelease];
}


- (id)initWithVector:(GSVector3)v
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
        vector = GSVector3_Make(v.x, v.y, v.z);
        cachedHash = [self computeHash];
    }
    
    return self;
}


- (GSVector3)vectorValue
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
    
    GSVector3 vector2 = [otherVector vectorValue];
    
    return GSVector3_AreEqual(vector, vector2);
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
    [self retain];
    return self;
}

@end


@implementation GSBoxedVector (Private)

- (NSUInteger)computeHash
{
    return GSVector3_Hash(vector);
}

@end
