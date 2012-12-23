//
//  GSQuaternion.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#include <math.h>
#include <assert.h>
#import <GLKit/GLKMath.h>
#include "GSQuaternion.h"

static const float EPSILON = 1e-8;


int GSQuaternion_AreEqual(GSQuaternion a, GSQuaternion b)
{
    return fabsf(a.x-b.x)<EPSILON && fabsf(a.y-b.y)<EPSILON && fabsf(a.z-b.z)<EPSILON && fabsf(a.w-b.w)<EPSILON;
}


int GSQuaternion_ToString(char * str, size_t len, GSQuaternion q)
{
    return snprintf(str, len, "GSQuaternion(%.2f, %.2f, %.2f, %.2f)", q.x, q.y, q.z, q.w);
}


GSQuaternion GSQuaternion_Normalize(GSQuaternion q)
{
    float mag2 = q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w;
    
    if(fabsf(mag2) > EPSILON && fabsf(mag2 - 1.0f) > EPSILON) {
        float mag = sqrt(mag2);
        
        return GSQuaternion_Make(q.x / mag,
                                 q.y / mag,
                                 q.z / mag,
                                 q.w / mag);
    } else {
        return q;
    }
}


GSQuaternion GSQuaternion_Conjugate(GSQuaternion q)
{
    return GSQuaternion_Make(-q.x, -q.y, -q.z, q.w);
}


GSQuaternion GSQuaternion_MulByQuat(GSQuaternion q1, GSQuaternion q2)
{
    float x1 = q1.x;
    float y1 = q1.y;
    float z1 = q1.z;
    float w1 = q1.w;
    
    float x2 = q2.x;
    float y2 = q2.y;
    float z2 = q2.z;
    float w2 = q2.w;
    
    float w3 = w1*w2 - x1*x2 - y1*y2 - z1*z2;
    float x3 = w1*x2 + x1*w2 + y1*z2 - z1*y2;
    float y3 = w1*y2 - x1*z2 + y1*w2 + z1*x2;
    float z3 = w1*z2 + x1*y2 - y1*x2 + z1*w2;
    
    return GSQuaternion_Make(x3, y3, z3, w3);
}


GLKVector3 GSQuaternion_MulByVec(GSQuaternion q, GLKVector3 v)
{
    GSQuaternion vAsQ = GSQuaternion_Make(v.x, v.y, v.z, 0);
    GSQuaternion q2 = GSQuaternion_MulByQuat(GSQuaternion_MulByQuat(q, vAsQ), GSQuaternion_Conjugate(q));
    return GLKVector3Make(q2.x, q2.y, q2.z);
}


GSQuaternion GSQuaternion_MakeFromAxisAngle(GLKVector3 v, float angle)
{
    GLKVector3 vn = GLKVector3Normalize(v);
    float sinAngle = sinf(angle / 2);
    return GSQuaternion_Make(vn.x * sinAngle,
                             vn.y * sinAngle,
                             vn.z * sinAngle,
                             cosf(angle / 2));
}


void GSQuaternion_ToAxisAngle(GSQuaternion self, GLKVector3 * pAxis, float * pAngle)
{
    float angle, scale;
    GLKVector3 axis;
    
    assert(pAxis);
    assert(pAngle);
    
    angle = 2.0f * acosf(self.w);
    scale = sqrt(1 - self.w*self.w);
    
    if(scale < EPSILON) {
        axis = GLKVector3Make(0, 1, 0);
    } else {        
        axis = GLKVector3Make(self.x / scale,
                              self.y / scale,
                              self.z / scale);

    }
    
    /* return through the pointer parameters */
    *pAxis = axis;
    *pAngle = angle;
}


GSQuaternion GSQuaternion_Make(float x, float y, float z, float w)
{
    GSQuaternion r = {x, y, z, w};
    return r;
}
