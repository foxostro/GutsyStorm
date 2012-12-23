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
    GLKVector3 origin, direction;
} GSRay;


GSRay GSRay_Make(GLKVector3 origin, GLKVector3 direction);
int GSRay_IntersectsPlane(GSRay ray, GSPlane plane, GLKVector3 *intersectionPointOut);
int GSRay_IntersectsAABB(GSRay ray, GLKVector3 minP, GLKVector3 maxP, float *distanceToEntrance, float *distanceToExit);

#endif
