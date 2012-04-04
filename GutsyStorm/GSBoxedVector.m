//
//  GSBoxedVector.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSBoxedVector.h"

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

@end
