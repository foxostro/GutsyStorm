//
//  GSRay.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdlib.h>
#include <math.h>
#include "GSRay.h"

#define TOP    (0)
#define BOTTOM (1)
#define LEFT   (2)
#define RIGHT  (3)
#define FRONT  (4)
#define BACK   (5)

#define MIN(a,b) ((a) < (b) ? (a) : (b))
#define MAX(a,b) ((a) > (b) ? (a) : (b))


static const float EPSILON = 1e-8;


GSRay GSRay_Make(GSVector3 origin, GSVector3 direction)
{
    GSRay ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}


int GSRay_IntersectsPlane(GSRay ray, GSPlane plane, GSVector3 *intersectionPointOut)
{
    float denominator = GSVector3_Dot(ray.direction, plane.n);
    
    if(fabsf(denominator) < EPSILON) {
        // Ray is parallel to the plane. So, it intersections at the origin.
        if(intersectionPointOut) {
            *intersectionPointOut = ray.origin;
        }
        return 1;
    }
    
    float d = -GSVector3_Dot(plane.p, plane.n);
    float numerator = -GSVector3_Dot(ray.origin, plane.n) + d;
    float t = numerator / denominator;
    
    if(t >= 0) {
        // Ray intersects plane.
        if(intersectionPointOut) {
            *intersectionPointOut = GSVector3_Add(ray.origin, GSVector3_Scale(ray.direction, t));
        }
        return 1;
    }
    
    // No intersection.
    return 0;
}


// Perform intersection test against the three front-facing planes and return the closest intersection.
int GSRay_IntersectsAABB(GSRay r, GSVector3 minP, GSVector3 maxP, float *intersectionDistanceOut)
{    
    GSVector3 dirfrac;
    float t = 0;
    
    dirfrac.x = 1.0f / r.direction.x;
    dirfrac.y = 1.0f / r.direction.y;
    dirfrac.z = 1.0f / r.direction.z;
    
    float t1 = (minP.x - r.origin.x)*dirfrac.x;
    float t2 = (maxP.x - r.origin.x)*dirfrac.x;
    float t3 = (minP.y - r.origin.y)*dirfrac.y;
    float t4 = (maxP.y - r.origin.y)*dirfrac.y;
    float t5 = (minP.z - r.origin.z)*dirfrac.z;
    float t6 = (maxP.z - r.origin.z)*dirfrac.z;
    
    float tmin = MAX(MAX(MIN(t1, t2), MIN(t3, t4)), MIN(t5, t6));
    float tmax = MIN(MIN(MAX(t1, t2), MAX(t3, t4)), MAX(t5, t6));
    
    // if tmax < 0, ray (line) is intersecting AABB, but whole AABB is behind us
    if (tmax < 0) {
        t = tmax;
        return 0;
    }
    
    // if tmin > tmax, ray doesn't intersect AABB
    if (tmin > tmax) {
        t = tmax;
        return 0;
    }
    
    t = tmin;
    
    if(intersectionDistanceOut) {
        *intersectionDistanceOut = t;
    }
    
    return 1;
}
