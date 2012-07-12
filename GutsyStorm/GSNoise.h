//
//  GSNoise.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"

@interface GSNoise : NSObject
{
    void *context;
}

- (id)initWithSeed:(unsigned)seed;
- (float)getNoiseAtPoint:(GSVector3)p;
- (float)getNoiseAtPoint:(GSVector3)p numOctaves:(unsigned)numOctaves;
- (float)getNoiseAtPointWithFourOctaves:(GSVector3)p;

@end
