//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSBoxedVector.h"

static const float EPS = 1e-5;


static NSUInteger sdbm(const size_t len, const char * str)
{
    // Source: <http://www.cse.yorku.ca/~oz/hash.html>
    
    NSUInteger hash = 0;
    
    for(size_t i = 0; i < len; ++i)
    {
        hash = str[i] + (hash << 6) + (hash << 16) - hash;
    }
    
    return hash;
}


@interface GSBoxedVector (Private)

- (NSUInteger)computeHash;

@end


@implementation GSBoxedVector

- (id)initWithVector:(GSVector3)v
{
    self = [super init];
    if (self) {
        // Initialization code here.
        [self setVector:v];
    }
    
    return self;
}


- (GSVector3)getVector
{
    return vector;
}


- (void)setVector:(GSVector3)v
{
    vector = v;
    cachedHash = [self computeHash];
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
    
    GSVector3 vector2 = [otherVector getVector];
    
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

@end


@implementation GSBoxedVector (Private)

- (NSUInteger)computeHash
{
    return sdbm(sizeof(vector), (const char *)&vector);
}

@end
