//
//  FoxVoxel.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "FoxIntegerVector3.h"
#import "FoxTerrainBuffer.h"
#import "FoxVoxel.h"

_Static_assert(sizeof(voxel_t) == sizeof(terrain_buffer_element_t),
               "voxel_t and terrain_buffer_element_t must be the same size");

const vector_long3 chunkSize = {CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};
const vector_long3 offsetForFace[FACE_NUM_FACES] =
{
    {0, +1, 0},
    {0, -1, 0},
    {0, 0, +1},
    {0, 0, -1},
    {+1, 0, 0},
    {-1, 0, 0}
};

const vector_long3 combinedMinP = {-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z};
const vector_long3 combinedMaxP = {2*CHUNK_SIZE_X, CHUNK_SIZE_Y, 2*CHUNK_SIZE_Z};