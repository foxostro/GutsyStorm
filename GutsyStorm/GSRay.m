//
//  GSRay.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <float.h>
#import "GSRay.h"

#define TOP    (0)
#define BOTTOM (1)
#define LEFT   (2)
#define RIGHT  (3)
#define FRONT  (4)
#define BACK   (5)


GSRay GSRayMake(vector_float3 origin, vector_float3 direction)
{
    GSRay ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}


int GSRayIntersectsPlane(GSRay ray, struct fox_plane plane, vector_float3 *intersectionPointOut)
{
    float denominator = vector_dot(ray.direction, plane.n);
    
    if(fabsf(denominator) < FLT_EPSILON) {
        // Ray is parallel to the plane. So, it intersections at the origin.
        if(intersectionPointOut) {
            *intersectionPointOut = ray.origin;
        }
        return 1;
    }
    
    float d = -vector_dot(plane.p, plane.n);
    float numerator = -vector_dot(ray.origin, plane.n) + d;
    float t = numerator / denominator;
    
    if(t >= 0) {
        // Ray intersects plane.
        if(intersectionPointOut) {
            *intersectionPointOut = ray.origin + (ray.direction * t);
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
int GSRayIntersectsAABB(GSRay r, vector_float3 minP, vector_float3 maxP,
						float *distanceToEntrance, float *distanceToExit)
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