//
//  GSNoise.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSNoise.h"
#include "snoise3.h"


@implementation GSNoise

- (id)initWithSeed:(unsigned)seed
{
    self = [super init];
    if (self) {
        // Initialization code here.
        context = FeepingCreature_CreateNoiseContext(&seed);
    }
    
    return self;
}


- (void)dealloc
{
    FeepingCreature_DestroyNoiseContext(context);
}


- (float)getNoiseAtPoint:(GSVector3)p
{
    return FeepingCreature_noise3(p, context);
}

@end