//
//  GSIntegerVector3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSIntegerVector3_h
#define GutsyStorm_GSIntegerVector3_h

typedef struct
{
    ssize_t x, y, z;
} GSIntegerVector3;

typedef GSIntegerVector3 GSNeighborOffset;

static inline GSIntegerVector3 GSIntegerVector3_Make(ssize_t x, ssize_t y, ssize_t z)
{
    return (GSIntegerVector3){x, y, z};
}

static inline GSIntegerVector3 GSIntegerVector3_MakeWithGLubyte3(GLbyte *v)
{
    return (GSIntegerVector3){v[0], v[1], v[2]};
}

static inline GSIntegerVector3 GSIntegerVector3_Add(GSIntegerVector3 a, GSIntegerVector3 b)
{
    return (GSIntegerVector3){a.x+b.x, a.y+b.y, a.z+b.z};
}

static const GSIntegerVector3 ivecZero = {0, 0, 0};

#endif
