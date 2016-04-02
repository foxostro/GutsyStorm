//
//  GSVectorUtils.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <simd/vector.h>

NSUInteger vector_hash(vector_float3 v);

static inline vector_float3 vector_make(float x, float y, float z)
{
    return (vector_float3){x, y, z};
}

static inline BOOL vector_equal(vector_float3 a, vector_float3 b)
{
    return (a.x == b.x) && (a.y == b.y) && (a.z == b.z);
}