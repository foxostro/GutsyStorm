//
//  GSChunkData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
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

+ (GLKVector3)centerPointOfChunkAtPoint:(GLKVector3)p
{
    return GLKVector3Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
}

+ (chunk_id_t)chunkIDWithChunkMinCorner:(GLKVector3)minP
{
    return [[GSBoxedVector alloc] initWithVector:minP];
}

- (id)initWithMinP:(GLKVector3)minP
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _minP = minP;
        _maxP = GLKVector3Add(_minP, GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        _centerP = GLKVector3MultiplyScalar(GLKVector3Add(_minP, _maxP), 0.5);
    }
    
    return self;
}

@end
