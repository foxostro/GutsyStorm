//
//  GSChunkData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "Chunk.h"
#import "GSChunkData.h"
#import "Voxel.h"
#import "GSBoxedVector.h"

const GSIntegerVector3 chunkSize = {CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};
const GSIntegerVector3 offsetForFace[FACE_NUM_FACES] =
{
    {0, +1, 0},
    {0, -1, 0},
    {0, 0, +1},
    {0, 0, -1},
    {+1, 0, 0},
    {-1, 0, 0}
};


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
