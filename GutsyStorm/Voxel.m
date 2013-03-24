//
//  Voxel.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKQuaternion.h>
#import "GSIntegerVector3.h"
#import "GSBuffer.h"
#import "Voxel.h"

_Static_assert(sizeof(voxel_t) == sizeof(buffer_element_t), "voxel_t and buffer_element_t must be the same size");

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

const GSIntegerVector3 combinedMinP = {-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z};
const GSIntegerVector3 combinedMaxP = {2*CHUNK_SIZE_X, CHUNK_SIZE_Y, 2*CHUNK_SIZE_Z};