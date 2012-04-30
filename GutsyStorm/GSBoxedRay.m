//
//  GSBoxedRay.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSBoxedRay.h"

@implementation GSBoxedRay

@synthesize ray;


- (id)initWithRay:(GSRay)_ray
{
    self = [super init];
    if (self) {
        // Initialization code here.
        ray = GSRay_Make(_ray.origin, _ray.direction);
    }
    
    return self;
}

@end
