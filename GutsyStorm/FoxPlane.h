//
//  FoxPlane.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_FoxPlane_h
#define GutsyStorm_FoxPlane_h

#include <simd/simd.h>

struct fox_plane
{
    vector_float3 p, n;
};


float fox_plane_distance(struct fox_plane plane, vector_float3 r);
struct fox_plane fox_plane_make(vector_float3 p0, vector_float3 p1, vector_float3 p2);

#endif
