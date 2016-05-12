//
//  GSAABB.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef GSAABB_h
#define GSAABB_h

typedef struct {
    vector_float3 mins, maxs;
} GSFloatAABB;

static inline BOOL GSFloatAABBIntersects(GSFloatAABB *a, GSFloatAABB *b)
{
    assert(a && b);
    BOOL intersects = (a->mins.x <= b->maxs.x) && (a->maxs.x >= b->mins.x) &&
                      (a->mins.y <= b->maxs.y) && (a->maxs.y >= b->mins.y) &&
                      (a->mins.z <= b->maxs.z) && (a->maxs.z >= b->mins.z);
    return intersects;
}

typedef struct {
    vector_long3 mins, maxs;
} GSIntAABB;

static inline BOOL GSIntAABBIntersects(GSIntAABB *a, GSIntAABB *b)
{
    assert(a && b);
    BOOL intersects = (a->mins.x <= b->maxs.x) && (a->maxs.x >= b->mins.x) &&
                      (a->mins.y <= b->maxs.y) && (a->maxs.y >= b->mins.y) &&
                      (a->mins.z <= b->maxs.z) && (a->maxs.z >= b->mins.z);
    return intersects;
}

#endif /* GSAABB_h */
