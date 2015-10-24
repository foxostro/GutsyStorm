//
//  FoxPlane.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#include "FoxPlane.h"

float fox_plane_distance(struct fox_plane plane, vector_float3 r)
{
    return vector_dot(plane.n, plane.p - r);
}

struct fox_plane fox_plane_make(vector_float3 p0, vector_float3 p1, vector_float3 p2)
{
    struct fox_plane plane;
    vector_float3 v = p1 - p0;
    vector_float3 u = p2 - p0;
    plane.n = vector_normalize(vector_cross(v, u));
    plane.p = p0;
    return plane;
}