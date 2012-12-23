//
//  GSNoise.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
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
    [super dealloc];
}


- (float)noiseAtPoint:(GLKVector3)p
{
    return FeepingCreature_noise3(p, context);
}


- (float)noiseAtPoint:(GLKVector3)p numOctaves:(unsigned)numOctaves
{
    const float persistence = 0.5;
    float noise = 0.0;
    
    for(unsigned octave = 0; octave < numOctaves; ++octave)
    {
        float frequency = pow(2, octave);
        float amplitude = pow(persistence, octave+1);
        noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, frequency), context) * amplitude;
    }
    
    return noise;
}


- (float)noiseAtPointWithFourOctaves:(GLKVector3)p
{
    float noise;
    
    noise =  FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 1.0f), context) * 0.5000f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 2.0f), context) * 0.2500f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 4.0f), context) * 0.1250f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 8.0f), context) * 0.0625f;
    
    return noise;
}


@end
