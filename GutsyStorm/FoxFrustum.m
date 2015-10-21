//
//  FoxFrustum.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <math.h>
#import "FoxFrustum.h"

#define TOP (0)
#define BOTTOM (1)
#define LEFT (2)
#define RIGHT (3)
#define NEARP (4)
#define FARP (5)


@implementation FoxFrustum

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        const vector_float3 zero = {0};
        bzero(pl, 6*sizeof(struct fox_plane));
        ntl = zero;
        ntr = zero;
        nbl = zero;
        nbr = zero;
        ftl = zero;
        ftr = zero;
        fbl = zero;
        fbr = zero;
        nearD = 0;
        farD = 0;
        ratio = 0;
        angle = 0;
        tang = 0;
        nw = 0;
        nh = 0;
        fw = 0;
        fh = 0;
    }
    
    return self;
}


/* This function takes exactly the same parameters as the function
 * gluPerspective. Each time the perspective definitions change, for
 * instance when a window is resized, this function should be called as
 * well.
 */
- (void)setCamInternalsWithAngle:(float)_angle ratio:(float)_ratio nearD:(float)_nearD farD:(float)_farD
{
    ratio = _ratio;
    angle = _angle;
    nearD = _nearD;
    farD = _farD;

    // compute width and height of the near and far plane sections
    tang = tanf(angle * 0.5);
    nh = nearD * tang;
    nw = nh * ratio;
    fh = farD * tang;
    fw = fh * ratio;
}


/* This function takes three vectors that contain the information for
 * the gluLookAt function: the position of the camera, a point to where
 * the camera is pointing and the up vector. Each time the camera position
 * or orientation changes, this function should be called as well.
 */
- (void)setCamDefWithCameraEye:(vector_float3)p cameraCenter:(vector_float3)l cameraUp:(vector_float3)u
{
    // compute the Z axis of camera
    // this axis points in the opposite direction from
    // the looking direction
    const vector_float3 Z = vector_normalize(l - p);

    // X axis of camera with given "up" vector and Z axis
    const vector_float3 X = vector_normalize(vector_cross(u, Z));

    // the real "up" vector is the cross product of Z and X
    const vector_float3 Y = vector_cross(Z, X);

    // compute the centers of the near and far planes
    const vector_float3 nc = p + (Z * nearD);
    const vector_float3 fc = p + (Z * farD);
    
    // compute the 4 corners of the frustum on the near plane
    const vector_float3 yScaledByNh = Y * nh;
    const vector_float3 xScaledByNw = X * nw;
    ntl = (nc + yScaledByNh) - xScaledByNw;
    ntr = nc + yScaledByNh + xScaledByNw;
    nbl = nc - yScaledByNh - xScaledByNw;
    nbr = (nc - yScaledByNh) + xScaledByNw;

    // compute the 4 corners of the frustum on the far plane
    const vector_float3 yScaledByFh = Y * fh;
    const vector_float3 xScaledByFw = X * fw;
    ftl = (fc + yScaledByFh) - xScaledByFw;
    ftr = (fc + yScaledByFh) + xScaledByFw;
    fbl = (fc - yScaledByFh) - xScaledByFw;
    fbr = (fc - yScaledByFh) + xScaledByFw;

    // compute the six planes
    // the function set3Points assumes that the points
    // are given in counter clockwise order
    pl[TOP]    = fox_plane_make(ntr, ntl, ftl);
    pl[BOTTOM] = fox_plane_make(nbl, nbr, fbr);
    pl[LEFT]   = fox_plane_make(ntl, nbl, fbl);
    pl[RIGHT]  = fox_plane_make(nbr, ntr, fbr);
    pl[NEARP]  = fox_plane_make(ntl, ntr, nbr);
    pl[FARP]   = fox_plane_make(ftr, ftl, fbl);
}


- (int)boxInFrustumWithBoxVertices:(vector_float3 *)vertices
{
    int result = FRUSTUM_INSIDE, out,in;
    
    // for each plane do ...
    for(int i=0; i < 6; i++) {
        
        // reset counters for corners in and out
        out=0;in=0;
        // for each corner of the box do ...
        // get out of the cycle as soon as a box as corners
        // both inside and out of the frustum
        for (int k = 0; k < 8 && (in==0 || out==0); k++) {
            
            // is the corner outside or inside
            if (fox_plane_distance(pl[i], vertices[k]) < 0)
                out++;
            else
                in++;
        }
        //if all corners are out
        if (!in)
            return (FRUSTUM_OUTSIDE);
        // if some corners are out and others are in    
        else if (out)
            result = FRUSTUM_INTERSECT;
    }
    return(result);
}

@end
