//
//  GSRay.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSRay_h
#define GutsyStorm_GSRay_h

#include "GSPlane.h"

typedef struct
{
    vector_float3 origin, direction;
} GSRay;


GSRay GSRay_Make(vector_float3 origin, vector_float3 direction);
int GSRay_IntersectsPlane(GSRay ray, GSPlane plane, vector_float3 *intersectionPointOut);
int GSRay_IntersectsAABB(GSRay ray, vector_float3 minP, vector_float3 maxP, float *distanceToEntrance, float *distanceToExit);

#endif
