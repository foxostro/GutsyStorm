//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSBoxedVector.h"

static const float EPS = 1e-5;

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
    cachedHash = [[self toString] hash];
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
    return [NSString stringWithFormat:@"%f_%f_%f", v.x, v.y, v.z];
}

@end
