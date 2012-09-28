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


static inline GSIntegerVector3 GSIntegerVector3_Make(ssize_t x, ssize_t y, ssize_t z)
{
    GSIntegerVector3 p = {x, y, z};
    return p;
}


static inline GSIntegerVector3 GSIntegerVector3_Add(GSIntegerVector3 a, GSIntegerVector3 b)
{
    GSIntegerVector3 p = {a.x+b.x, a.y+b.y, a.z+b.z};
    return p;
}

static const GSIntegerVector3 ivecZero = {0, 0, 0};

#endif
