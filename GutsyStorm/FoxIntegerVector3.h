//
//  FoxIntegerVector3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/18/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_FoxIntegerVector3_h
#define GutsyStorm_FoxIntegerVector3_h

#import <simd/vector.h>

static inline vector_long3 fox_ivec3_make(ssize_t x, ssize_t y, ssize_t z)
{
    return (vector_long3){x, y, z};
}

static inline vector_long3 fox_ivec3_make_with_bytes(int8_t *v)
{
    return (vector_long3){v[0], v[1], v[2]};
}

static const vector_long3 ivecZero = {0, 0, 0};

#endif