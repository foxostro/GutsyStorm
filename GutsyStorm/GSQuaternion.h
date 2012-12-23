//
//  GSQuaternion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSQuaternion_h
#define GutsyStorm_GSQuaternion_h

typedef struct
{
    float x, y, z, w;
} GSQuaternion;

int GSQuaternion_AreEqual(GSQuaternion a, GSQuaternion b);
int GSQuaternion_ToString(char * str, size_t len, GSQuaternion q);
GSQuaternion GSQuaternion_Normalize(GSQuaternion q);
GSQuaternion GSQuaternion_Conjugate(GSQuaternion q);
GSQuaternion GSQuaternion_MulByQuat(GSQuaternion a, GSQuaternion b);
GLKVector3 GSQuaternion_MulByVec(GSQuaternion a, GLKVector3 b);
GSQuaternion GSQuaternion_MakeFromAxisAngle(GLKVector3 v, float angle);
void GSQuaternion_ToAxisAngle(GSQuaternion q, GLKVector3 * axis, float * angle);
GSQuaternion GSQuaternion_Make(float x, float y, float z, float w);

#endif
