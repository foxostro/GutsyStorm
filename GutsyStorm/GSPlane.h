//
//  GSPlane.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSPlane_h
#define GutsyStorm_GSPlane_h

#include <simd/simd.h>

typedef struct
{
    vector_float3 p, n;
} GSPlane;


float GSPlane_Distance(GSPlane plane, vector_float3 r);
GSPlane GSPlane_MakeFromPoints(vector_float3 p0, vector_float3 p1, vector_float3 p2);

#endif
