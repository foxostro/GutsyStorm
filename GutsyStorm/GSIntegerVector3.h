//
//  GSIntegerVector3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/18/12.
//  Copyright 2012-2016 Andrew Fox. All rights reserved.
//

#import <simd/vector.h>

static inline vector_long3 GSMakeIntegerVector3(long x, long y, long z)
{
    return (vector_long3){x, y, z};
}

static inline vector_long3 GSCastToIntegerVector3(vector_float3 v)
{
    return (vector_long3){v.x, v.y, v.z};
}

static inline vector_float3 GSCastToFloat3(vector_long3 v)
{
    return (vector_float3){v.x, v.y, v.z};
}

static const vector_long3 GSZeroIntVec3 = {0, 0, 0};