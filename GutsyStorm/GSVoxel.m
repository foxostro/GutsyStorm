//
//  GSVoxel.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSTerrainBuffer.h"
#import "GSVoxel.h"

_Static_assert(sizeof(GSVoxel) == sizeof(GSTerrainBufferElement),
               "GSVoxel and GSTerrainBufferElement must be the same size");

const vector_long3 GSChunkSizeIntVec3 = {CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z};
const vector_long3 GSOffsetForVoxelFace[FACE_NUM_FACES] =
{
    {0, +1, 0},
    {0, -1, 0},
    {0, 0, +1},
    {0, 0, -1},
    {+1, 0, 0},
    {-1, 0, 0}
};

const vector_long3 GSCombinedMinP = {-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z};
const vector_long3 GSCombinedMaxP = {2*CHUNK_SIZE_X, CHUNK_SIZE_Y, 2*CHUNK_SIZE_Z};