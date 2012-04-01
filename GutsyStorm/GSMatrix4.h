//
//  GSMatrix4.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/1/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSMatrix4_h
#define GutsyStorm_GSMatrix4_h

#include "GSVector3.h"
#include "GSVector4.h"


typedef struct
{
	float m[16];
} GSMatrix4;


GSMatrix4 GSMatrix4_Identity(void);
GSMatrix4 GSMatrix4_MulByMat(GSMatrix4 m1, GSMatrix4 m2);
GSMatrix4 GSMatrix4_Translate(GSVector3 v);
GSMatrix4 GSMatrix4_Scale(GSVector3 v);
GSVector3 GSMatrix4_ProjVec3(GSMatrix4 m, GSVector3 v);
GSVector4 GSMatrix4_ProjVec4(GSMatrix4 m, GSVector4 v);

#endif
