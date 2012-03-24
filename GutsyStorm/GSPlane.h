//
//  GSPlane.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSPlane_h
#define GutsyStorm_GSPlane_h

#include "GSVector3.h"

typedef struct
{
	GSVector3 p, n;
} GSPlane;


float GSPlane_Distance(GSPlane plane, GSVector3 r);
GSPlane GSPlane_MakeFromPoints(GSVector3 p0, GSVector3 p1, GSVector3 p2);

#endif
