//
//  GSPlane.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdlib.h>
#import <GLKit/GLKMath.h>
#include "GSPlane.h"


float GSPlane_Distance(GSPlane plane, GLKVector3 r)
{
    return GLKVector3DotProduct(plane.n, GLKVector3Subtract(plane.p, r));
}


GSPlane GSPlane_MakeFromPoints(GLKVector3 p0, GLKVector3 p1, GLKVector3 p2)
{
    GSPlane plane;
    GLKVector3 v = GLKVector3Subtract(p1, p0);
    GLKVector3 u = GLKVector3Subtract(p2, p0);
    plane.n = GLKVector3Normalize(GLKVector3CrossProduct(v, u));
    plane.p = p0;
    return plane;
}
