//
//  GSPlane.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdlib.h>
#include "GSPlane.h"


float GSPlane_Distance(GSPlane plane, GSVector3 r)
{
    return GSVector3_Dot(plane.n, GSVector3_Sub(plane.p, r));
}


GSPlane GSPlane_MakeFromPoints(GSVector3 p0, GSVector3 p1, GSVector3 p2)
{
    GSPlane plane;
    GSVector3 v = GSVector3_Sub(p1, p0);
    GSVector3 u = GSVector3_Sub(p2, p0);
    plane.n = GSVector3_Normalize(GSVector3_Cross(v, u));
    plane.p = p0;
    return plane;
}
