//
//  GSChunkSunlightData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSChunkSunlightData.h"
#import "GSMutableBuffer.h"

@implementation GSChunkSunlightData

@synthesize minP;

- (id)initWithMinP:(GLKVector3)minCorner
            folder:(NSURL *)folder
      neighborhood:(GSNeighborhood *)neighborhood
{
    if(self = [super init]) {
        minP = minCorner;
        _neighborhood = neighborhood;

        GSIntegerVector3 dim = GSIntegerVector3_Make(CHUNK_SIZE_X+2, CHUNK_SIZE_Y, CHUNK_SIZE_Z+2);
        size_t len = BUFFER_SIZE_IN_BYTES(dim);
        buffer_element_t *data = malloc(len);
        for(size_t i=0; i<(len / sizeof(buffer_element_t)); ++i)
        {
            data[i] = CHUNK_LIGHTING_MAX / 2; // TODO: reimplement sunlight generation
        }

        _sunlight = [[GSMutableBuffer alloc] initWithDimensions:dim data:data];

        free(data);
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self; // GSChunkSunlightData is immutable, so return self instead of deep copying
}

@end
