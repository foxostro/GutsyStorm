//
//  GSAABB.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef GSAABB_h
#define GSAABB_h

#import <Foundation/Foundation.h>
#import "GSBoxedVector.h"


typedef struct {
    vector_float3 mins, maxs;
} GSFloatAABB;

static inline BOOL GSFloatAABBIntersects(GSFloatAABB a, GSFloatAABB b)
{
    BOOL intersects = (a.mins.x <= b.maxs.x) && (a.maxs.x >= b.mins.x) &&
                      (a.mins.y <= b.maxs.y) && (a.maxs.y >= b.mins.y) &&
                      (a.mins.z <= b.maxs.z) && (a.maxs.z >= b.mins.z);
    return intersects;
}

static inline NSString * _Nonnull GSFloatAABBDescription(GSFloatAABB box)
{
    return [NSString stringWithFormat:@"[%@,%@]",
            [GSBoxedVector boxedVectorWithVector:box.mins],
            [GSBoxedVector boxedVectorWithVector:box.maxs]];
}


typedef struct {
    vector_long3 mins, maxs;
} GSIntAABB;

static inline BOOL GSIntAABBIntersects(GSIntAABB a, GSIntAABB b)
{
    BOOL intersects = (a.mins.x <= b.maxs.x) && (a.maxs.x >= b.mins.x) &&
                      (a.mins.y <= b.maxs.y) && (a.maxs.y >= b.mins.y) &&
                      (a.mins.z <= b.maxs.z) && (a.maxs.z >= b.mins.z);
    return intersects;
}

static inline BOOL GSIntAABBPointInBox(GSIntAABB b, vector_long3 p)
{
    BOOL intersects = (p.x <= b.maxs.x) && (p.x >= b.mins.x) &&
                      (p.y <= b.maxs.y) && (p.y >= b.mins.y) &&
                      (p.z <= b.maxs.z) && (p.z >= b.mins.z);
    return intersects;
}

static inline NSString * _Nonnull GSIntAABBDescription(GSIntAABB box)
{
    return [NSString stringWithFormat:@"[%@,%@]",
            [GSBoxedVector boxedVectorWithIntegerVector:box.mins],
            [GSBoxedVector boxedVectorWithIntegerVector:box.maxs]];
}

#endif /* GSAABB_h */
