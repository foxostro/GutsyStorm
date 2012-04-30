//
//  GSChunkData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkData.h"

@implementation GSChunkData

@synthesize minP;
@synthesize maxP;
@synthesize centerP;

- (id)initWithMinP:(GSVector3)_minP
{
    self = [super init];
    if (self) {
        // Initialization code here.
        minP = _minP;
        maxP = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        centerP = GSVector3_Scale(GSVector3_Add(minP, maxP), 0.5);
    }
    
    return self;
}

@end
