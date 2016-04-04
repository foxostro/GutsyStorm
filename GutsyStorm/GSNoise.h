//
//  GSNoise.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <simd/simd.h>

@interface GSNoise : NSObject

- (nonnull instancetype)initWithSeed:(NSUInteger)seed;
- (float)noiseAtPoint:(vector_float3)p;
- (float)noiseAtPoint:(vector_float3)p numOctaves:(NSUInteger)numOctaves;
- (float)noiseAtPointWithFourOctaves:(vector_float3)p;

@end
