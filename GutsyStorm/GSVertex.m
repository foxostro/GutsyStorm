//
//  GSVertex.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GLKVector3Extra.h"
#import "GSVertex.h"

@implementation GSVertex

@synthesize v;

- (id)initWithVertex:(struct vertex *)pv
{
    assert(pv);
    
    self = [super init];
    if (self) {
        v = *pv;
    }

    return self;
}

- (void)dealloc
{
    [super dealloc];
}

@end
