//
//  GSNoise.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSNoise.h"
#include "snoise3.h"


@implementation GSNoise
{
    void *_context;
}

- (nonnull instancetype)initWithSeed:(NSUInteger)seed
{
    self = [super init];
    if (self) {
        // Initialization code here.
        assert(seed < UINT_MAX);
        unsigned s = (unsigned)seed;
        _context = FeepingCreature_CreateNoiseContext(&s);
        if (!_context) {
            [NSException raise:@"Out of Memory" format:@"Failed to create noise context in GSNoise."];
        }
    }
    
    return self;
}

- (void)dealloc
{
    FeepingCreature_DestroyNoiseContext(_context);
}

- (float)noiseAtPoint:(vector_float3)p
{
    return FeepingCreature_noise3(p, _context);
}

- (float)noiseAtPoint:(vector_float3)p numOctaves:(NSUInteger)numOctaves
{
    const float persistence = 0.5;
    float noise = 0.0;
    
    for(NSUInteger octave = 0; octave < numOctaves; ++octave)
    {
        float frequency = pow(2, octave);
        float amplitude = pow(persistence, octave+1);
        noise += FeepingCreature_noise3(p * frequency, _context) * amplitude;
    }
    
    return noise;
}

- (float)noiseAtPointWithFourOctaves:(vector_float3)p
{
    float noise;
    
    noise =  FeepingCreature_noise3(p * 1.0f, _context) * 0.5000f;
    noise += FeepingCreature_noise3(p * 2.0f, _context) * 0.2500f;
    noise += FeepingCreature_noise3(p * 4.0f, _context) * 0.1250f;
    noise += FeepingCreature_noise3(p * 8.0f, _context) * 0.0625f;
    
    return noise;
}

@end
