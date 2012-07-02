//
//  GSRay.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSRay_h
#define GutsyStorm_GSRay_h

#include "GSVector3.h"
#include "GSPlane.h"

typedef struct
{
    GSVector3 origin, direction;
} GSRay;


GSRay GSRay_Make(GSVector3 origin, GSVector3 direction);
int GSRay_IntersectsPlane(GSRay ray, GSPlane plane, GSVector3 *intersectionPointOut);
int GSRay_IntersectsAABB(GSRay ray, GSVector3 minP, GSVector3 maxP, float *distanceToEntrance, float *distanceToExit);

#endif
