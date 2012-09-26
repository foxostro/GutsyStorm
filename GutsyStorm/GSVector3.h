//
//  GSVector3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSVector3_h
#define GutsyStorm_GSVector3_h

typedef struct
{
    float x, y, z;
} GSVector3;

float GSVector3_Length(GSVector3 v);
GSVector3 GSVector3_Normalize(GSVector3 v);
GSVector3 GSVector3_Add(GSVector3 a, GSVector3 b);
GSVector3 GSVector3_Sub(GSVector3 a, GSVector3 b);
float GSVector3_Dot(GSVector3 a, GSVector3 b);
GSVector3 GSVector3_Cross(GSVector3 a, GSVector3 b);
int GSVector3_ToString(char * str, size_t len, GSVector3 v);
int GSVector3_AreEqual(GSVector3 a, GSVector3 b);
GSVector3 GSVector3_Scale(GSVector3 v, float scale);
GSVector3 GSVector3_Make(float x, float y, float z);
size_t GSVector3_Hash(GSVector3 v);

#endif
