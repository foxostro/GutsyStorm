//
//  Chunk.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Chunk_h
#define GutsyStorm_Chunk_h

#define CHUNK_SIZE_X (16)
#define CHUNK_SIZE_Y (128)
#define CHUNK_SIZE_Z (16)

static inline GLKVector3 MinCornerForChunkAtPoint(GLKVector3 p)
{
    return GLKVector3Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}

static inline GLKVector3 MinCornerForChunkAtPoint2(float x, float y, float z)
{
    return GLKVector3Make(floorf(x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}

#endif
