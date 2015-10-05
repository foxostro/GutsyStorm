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
{
    void *_context;
}

- (instancetype)initWithSeed:(NSUInteger)seed
{
    self = [super init];
    if (self) {
        // Initialization code here.
        assert(seed < UINT_MAX);
        unsigned s = (unsigned)seed;
        _context = FeepingCreature_CreateNoiseContext(&s);
    }
    
    return self;
}

- (void)dealloc
{
    FeepingCreature_DestroyNoiseContext(_context);
}

- (float)noiseAtPoint:(GLKVector3)p
{
    return FeepingCreature_noise3(p, _context);
}

- (float)noiseAtPoint:(GLKVector3)p numOctaves:(NSUInteger)numOctaves
{
    const float persistence = 0.5;
    float noise = 0.0;
    
    for(NSUInteger octave = 0; octave < numOctaves; ++octave)
    {
        float frequency = pow(2, octave);
        float amplitude = pow(persistence, octave+1);
        noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, frequency), _context) * amplitude;
    }
    
    return noise;
}

- (float)noiseAtPointWithFourOctaves:(GLKVector3)p
{
    float noise;
    
    noise =  FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 1.0f), _context) * 0.5000f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 2.0f), _context) * 0.2500f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 4.0f), _context) * 0.1250f;
    noise += FeepingCreature_noise3(GLKVector3MultiplyScalar(p, 8.0f), _context) * 0.0625f;
    
    return noise;
}

@end
