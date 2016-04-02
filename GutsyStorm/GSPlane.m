//
//  GSPlane.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSPlane.h"

float GSPlaneDistance(GSPlane plane, vector_float3 r)
{
    return vector_dot(plane.n, plane.p - r);
}

GSPlane GSPlaneMake(vector_float3 p0, vector_float3 p1, vector_float3 p2)
{
    GSPlane plane;
    vector_float3 v = p1 - p0;
    vector_float3 u = p2 - p0;
    plane.n = vector_normalize(vector_cross(v, u));
    plane.p = p0;
    return plane;
}