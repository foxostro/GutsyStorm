//
//  GSRay.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdlib.h>
#include <math.h>
#import <GLKit/GLKMath.h>
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


GSRay GSRay_Make(GLKVector3 origin, GLKVector3 direction)
{
    GSRay ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}


int GSRay_IntersectsPlane(GSRay ray, GSPlane plane, GLKVector3 *intersectionPointOut)
{
    float denominator = GLKVector3DotProduct(ray.direction, plane.n);
    
    if(fabsf(denominator) < EPSILON) {
        // Ray is parallel to the plane. So, it intersections at the origin.
        if(intersectionPointOut) {
            *intersectionPointOut = ray.origin;
        }
        return 1;
    }
    
    float d = -GLKVector3DotProduct(plane.p, plane.n);
    float numerator = -GLKVector3DotProduct(ray.origin, plane.n) + d;
    float t = numerator / denominator;
    
    if(t >= 0) {
        // Ray intersects plane.
        if(intersectionPointOut) {
            *intersectionPointOut = GLKVector3Add(ray.origin, GLKVector3MultiplyScalar(ray.direction, t));
        }
        return 1;
    }
    
    // No intersection.
    return 0;
}


/* Perform intersection test against the three front-facing planes and return the intersection distance where the ray enters and 
 * exits the box. If the ray originates within the box then distanceToEntrance will be set to NAN.
 * Returns 1 if there is an intersection, and 0 if there is no intersection at all.
 */
int GSRay_IntersectsAABB(GSRay r, GLKVector3 minP, GLKVector3 maxP, float *distanceToEntrance, float *distanceToExit)
{
	struct {
		float t1, t2;
	} slabT[3] = { {(minP.x - r.origin.x) / r.direction.x, (maxP.x - r.origin.x) / r.direction.x},
				   {(minP.y - r.origin.y) / r.direction.y, (maxP.y - r.origin.y) / r.direction.y},
		           {(minP.z - r.origin.z) / r.direction.z, (maxP.z - r.origin.z) / r.direction.z}
	};
	
	if(r.origin.x >= minP.x &&
	   r.origin.x <= maxP.x &&
	   r.origin.y >= minP.y &&
	   r.origin.y <= maxP.y &&
	   r.origin.z >= minP.z &&
	   r.origin.z <= maxP.z) {
		// The ray originates within the box and we are only looking for the exit point.
		// exitT is the closest intersection distance
		float exitT = INFINITY;
		
		for(size_t i = 0; i < 3; ++i)
		{
			if(slabT[i].t1 > 0.0 && fabsf(slabT[i].t1) < fabsf(exitT)) {
				exitT = slabT[i].t1;
			}
			
			if(slabT[i].t2 > 0.0 && fabsf(slabT[i].t2) < fabsf(exitT)) {
				exitT = slabT[i].t2;
			}
		}
		
		if(distanceToEntrance) {
			*distanceToEntrance = NAN;
		}
		
        if(distanceToExit) {
			*distanceToExit = exitT;
		}
	} else {
		// enterT is the closest intersection distance
		// exitT is the second closest intersection distance
		float enterT = INFINITY, exitT = INFINITY;
		
		for(size_t i = 0; i < 3; ++i)
		{
			if(slabT[i].t1 > 0.0 && fabsf(slabT[i].t1) < fabsf(enterT)) {
				enterT = slabT[i].t1;
			}
			
			if(slabT[i].t2 > 0.0 && fabsf(slabT[i].t2) < fabsf(enterT)) {
				enterT = slabT[i].t2;
			}
		}
		
		for(size_t i = 0; i < 3; ++i)
		{
			if(slabT[i].t1 > 0.0 && fabsf(slabT[i].t1) < fabsf(exitT) && fabsf(slabT[i].t1) > fabsf(enterT)) {
				exitT = slabT[i].t1;
			}
			
			if(slabT[i].t2 > 0.0 && fabsf(slabT[i].t2) < fabsf(exitT) && fabsf(slabT[i].t2) > fabsf(enterT)) {
				exitT = slabT[i].t2;
			}
		}
		
		// The ray does not originate within the box so there is definitely an entrance and an exit point. (These may be the same.)
		if(distanceToEntrance) {
			*distanceToEntrance = enterT;
		}
		
        if(distanceToExit) {
			*distanceToExit = exitT;
		}
	}
    
    return 1;
}