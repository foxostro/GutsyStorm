//
//  FoxRay.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Fox_Ray_h
#define GutsyStorm_Fox_Ray_h

#include "FoxPlane.h"

struct fox_ray
{
    vector_float3 origin, direction;
};


struct fox_ray fox_ray_make(vector_float3 origin, vector_float3 direction);
int fox_ray_intersects_plane(struct fox_ray ray, struct fox_plane plane, vector_float3 *intersectionPointOut);
int fox_ray_intersects_aabb(struct fox_ray ray, vector_float3 minP, vector_float3 maxP,
                         float *distanceToEntrance, float *distanceToExit);

#endif