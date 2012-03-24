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

- (id)initWithSeed:(unsigned)seed;
- (float)getNoiseAtPoint:(GSVector3)p;

@end
