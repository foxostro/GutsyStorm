//
//  GSChunkData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSChunkData.h"


@implementation GSChunkData

- (id)initWithMinP:(GLKVector3)minP
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _minP = minP;
    }
    
    return self;
}

@end
