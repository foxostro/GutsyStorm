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

@synthesize v;

- (id)initWithVector:(GSVector3)_v
{
    self = [super init];
    if (self) {
        // Initialization code here.
        v = _v;
    }
    
    return self;
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


- (BOOL)isEqualToVector:(GSBoxedVector *)vector
{
    if(self == vector) {
        return YES;
    }
    
    return (fabs(vector.v.x - self.v.x) < EPS &&
            fabs(vector.v.y - self.v.y) < EPS &&
            fabs(vector.v.z - self.v.z) < EPS);
}


- (NSUInteger)hash
{
    return [[self toString] hash];
}


- (NSString *)toString
{
    return [NSString stringWithFormat:@"%f_%f_%f", v.x, v.y, v.z];
}

@end
