//
//  FoxNoise.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <simd/simd.h>

@interface FoxNoise : NSObject

// XXX: We need a noise API that generates batch noise. For example, it could fill an array with 3D noise.

- (instancetype)initWithSeed:(NSUInteger)seed;
- (float)noiseAtPoint:(vector_float3)p;
- (float)noiseAtPoint:(vector_float3)p numOctaves:(NSUInteger)numOctaves;
- (float)noiseAtPointWithFourOctaves:(vector_float3)p;

@end
