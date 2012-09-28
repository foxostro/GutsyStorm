//
//  GSChunkData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkData.h"
#import "Voxel.h"
#import "GSBoxedVector.h"

const GSIntegerVector3 chunkSize = {CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};

@implementation GSChunkData

@synthesize minP;
@synthesize maxP;
@synthesize centerP;

+ (GSVector3)minCornerForChunkAtPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}

+ (GSVector3)centerPointOfChunkAtPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
}

+ (chunk_id_t)chunkIDWithChunkMinCorner:(GSVector3)minP
{
    return [[[GSBoxedVector alloc] initWithVector:minP] autorelease];
}

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
