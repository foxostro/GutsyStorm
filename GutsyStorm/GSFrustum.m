//
//  GSFrustum.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>
#import <GLKit/GLKMath.h>
#import <math.h>
#import "GSFrustum.h"

#define TOP (0)
#define BOTTOM (1)
#define LEFT (2)
#define RIGHT (3)
#define NEARP (4)
#define FARP (5)


@implementation GSFrustum

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        const GLKVector3 zero = GLKVector3Make(0,0,0);
        bzero(pl, 6*sizeof(GSPlane));
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
- (void)setCamDefWithCameraEye:(GLKVector3)p cameraCenter:(GLKVector3)l cameraUp:(GLKVector3)u
{
    // compute the Z axis of camera
    // this axis points in the opposite direction from
    // the looking direction
    const GLKVector3 Z = GLKVector3Normalize(GLKVector3Subtract(l, p));

    // X axis of camera with given "up" vector and Z axis
    const GLKVector3 X = GLKVector3Normalize(GLKVector3CrossProduct(u, Z));

    // the real "up" vector is the cross product of Z and X
    const GLKVector3 Y = GLKVector3CrossProduct(Z, X);

    // compute the centers of the near and far planes
    const GLKVector3 nc = GLKVector3Add(p, GLKVector3MultiplyScalar(Z, nearD));
    const GLKVector3 fc = GLKVector3Add(p, GLKVector3MultiplyScalar(Z, farD));
    
    // compute the 4 corners of the frustum on the near plane
    const GLKVector3 yScaledByNh = GLKVector3MultiplyScalar(Y, nh);
    const GLKVector3 xScaledByNw = GLKVector3MultiplyScalar(X, nw);
    ntl = GLKVector3Subtract(GLKVector3Add(nc, yScaledByNh), xScaledByNw);
    ntr = GLKVector3Add(GLKVector3Add(nc, yScaledByNh), xScaledByNw);
    nbl = GLKVector3Subtract(GLKVector3Subtract(nc, yScaledByNh), xScaledByNw);
    nbr = GLKVector3Add(GLKVector3Subtract(nc, yScaledByNh), xScaledByNw);

    // compute the 4 corners of the frustum on the far plane
    const GLKVector3 yScaledByFh = GLKVector3MultiplyScalar(Y, fh);
    const GLKVector3 xScaledByFw = GLKVector3MultiplyScalar(X, fw);
    ftl = GLKVector3Subtract(GLKVector3Add(fc, yScaledByFh), xScaledByFw);
    ftr = GLKVector3Add(GLKVector3Add(fc, yScaledByFh), xScaledByFw);
    fbl = GLKVector3Subtract(GLKVector3Subtract(fc, yScaledByFh), xScaledByFw);
    fbr = GLKVector3Add(GLKVector3Subtract(fc, yScaledByFh), xScaledByFw);

    // compute the six planes
    // the function set3Points assumes that the points
    // are given in counter clockwise order
    pl[TOP]    = GSPlane_MakeFromPoints(ntr, ntl, ftl);
    pl[BOTTOM] = GSPlane_MakeFromPoints(nbl, nbr, fbr);
    pl[LEFT]   = GSPlane_MakeFromPoints(ntl, nbl, fbl);
    pl[RIGHT]  = GSPlane_MakeFromPoints(nbr, ntr, fbr);
    pl[NEARP]  = GSPlane_MakeFromPoints(ntl, ntr, nbr);
    pl[FARP]   = GSPlane_MakeFromPoints(ftr, ftl, fbl);
}


- (int)boxInFrustumWithBoxVertices:(GLKVector3 *)vertices
{
    int result = GS_FRUSTUM_INSIDE, out,in;
    
    // for each plane do ...
    for(int i=0; i < 6; i++) {
        
        // reset counters for corners in and out
        out=0;in=0;
        // for each corner of the box do ...
        // get out of the cycle as soon as a box as corners
        // both inside and out of the frustum
        for (int k = 0; k < 8 && (in==0 || out==0); k++) {
            
            // is the corner outside or inside
            if (GSPlane_Distance(pl[i], vertices[k]) < 0)
                out++;
            else
                in++;
        }
        //if all corners are out
        if (!in)
            return (GS_FRUSTUM_OUTSIDE);
        // if some corners are out and others are in    
        else if (out)
            result = GS_FRUSTUM_INTERSECT;
    }
    return(result);
}


// For debugging, draw the frustum using OpenGL.
- (void)draw
{
    glDisable(GL_LIGHTING);
    glDisable(GL_TEXTURE_2D);
    
    glColor4f(0.0, 1.0, 0.0, 1.0);
    
    glBegin(GL_LINE_LOOP);
    glVertex3f(ntl.x, ntl.y, ntl.z);
    glVertex3f(ntr.x, ntr.y, ntr.z);
    glVertex3f(nbr.x, nbr.y, nbr.z);
    glVertex3f(nbl.x, nbl.y, nbl.z);
    glEnd();
    
    glBegin(GL_LINE_LOOP);
    glVertex3f(ftl.x, ftl.y, ftl.z);
    glVertex3f(ftr.x, ftr.y, ftr.z);
    glVertex3f(fbr.x, fbr.y, fbr.z);
    glVertex3f(fbl.x, fbl.y, fbl.z);
    glEnd();
    
    glBegin(GL_LINES);
    glVertex3f(ntl.x, ntl.y, ntl.z);
    glVertex3f(ftl.x, ftl.y, ftl.z);
    glVertex3f(ntr.x, ntr.y, ntr.z);
    glVertex3f(ftr.x, ftr.y, ftr.z);
    glVertex3f(nbl.x, nbl.y, nbl.z);
    glVertex3f(fbl.x, fbl.y, fbl.z);
    glVertex3f(nbr.x, nbr.y, nbr.z);
    glVertex3f(fbr.x, fbr.y, fbr.z);
    glEnd();
    
    glColor4f(1.0, 1.0, 1.0, 1.0);
    glBegin(GL_LINES);
    for(int i = 0; i < 6; ++i)
    {
        GLKVector3 p1 = pl[i].p;
        GLKVector3 p2 = GLKVector3Add(pl[i].p, pl[i].n);
        
        glVertex3f(p1.x, p1.y, p1.z);
        glVertex3f(p2.x, p2.y, p2.z);
    }
    glEnd();
    
    glEnable(GL_LIGHTING);
    glEnable(GL_TEXTURE_2D);
}

@end
