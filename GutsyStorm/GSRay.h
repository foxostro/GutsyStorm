//
//  GSRay.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#include "GSPlane.h"

typedef struct
{
    vector_float3 origin, direction;
} GSRay;


GSRay GSRayMake(vector_float3 origin, vector_float3 direction);
int GSRayIntersectsPlane(GSRay ray, GSPlane plane, vector_float3 * _Nullable intersectionPointOut);
int GSRayIntersectsAABB(GSRay ray, vector_float3 minP, vector_float3 maxP,
                        float * _Nullable distanceToEntrance, float * _Nullable distanceToExit);
