//
//  GSPlane.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSPlane_h
#define GutsyStorm_GSPlane_h

typedef struct
{
    GLKVector3 p, n;
} GSPlane;


float GSPlane_Distance(GSPlane plane, GLKVector3 r);
GSPlane GSPlane_MakeFromPoints(GLKVector3 p0, GLKVector3 p1, GLKVector3 p2);

#endif
