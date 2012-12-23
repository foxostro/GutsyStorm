//
//  GSMatrix4.c
//  GutsyStorm
//
//  Created by Andrew Fox on 4/1/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#import <GLKit/GLKMath.h>
#include "GSMatrix4.h"


GSMatrix4 GSMatrix4_Identity(void)
{
    GSMatrix4 identity;
    
    identity.m[0]  = identity.m[5]  = identity.m[10] = identity.m[15] = 1.0;
    identity.m[1]  = identity.m[2]  = identity.m[3]  = identity.m[4]  = 0.0;
    identity.m[6]  = identity.m[7]  = identity.m[8]  = identity.m[9]  = 0.0;    
    identity.m[11] = identity.m[12] = identity.m[13] = identity.m[14] = 0.0;
    
    return identity;
}


GSMatrix4 GSMatrix4_MulByMat(GSMatrix4 m1, GSMatrix4 m2)
{
    GSMatrix4 result;
    
    result.m[0]  = m1.m[0] * m2.m[0]  + m1.m[4] * m2.m[1]  + m1.m[8]  * m2.m[2] + m1.m[12] * m2.m[3];
    result.m[1]  = m1.m[1] * m2.m[0]  + m1.m[5] * m2.m[1]  + m1.m[9]  * m2.m[2] + m1.m[13] * m2.m[3];
    result.m[2]  = m1.m[2] * m2.m[0]  + m1.m[6] * m2.m[1]  + m1.m[10] * m2.m[2] + m1.m[14] * m2.m[3];
    result.m[3]  = m1.m[3] * m2.m[0]  + m1.m[7] * m2.m[1]  + m1.m[11] * m2.m[2] + m1.m[15] * m2.m[3];
    
    result.m[4]  = m1.m[0] * m2.m[4]  + m1.m[4] * m2.m[5]  + m1.m[8]  * m2.m[6] + m1.m[12] * m2.m[7];
    result.m[5]  = m1.m[1] * m2.m[4]  + m1.m[5] * m2.m[5]  + m1.m[9]  * m2.m[6] + m1.m[13] * m2.m[7];
    result.m[6]  = m1.m[2] * m2.m[4]  + m1.m[6] * m2.m[5]  + m1.m[10] * m2.m[6] + m1.m[14] * m2.m[7];
    result.m[7]  = m1.m[3] * m2.m[4]  + m1.m[7] * m2.m[5]  + m1.m[11] * m2.m[6] + m1.m[15] * m2.m[7];
    
    result.m[8]  = m1.m[0] * m2.m[8]  + m1.m[4] * m2.m[9]  + m1.m[8]  * m2.m[10] + m1.m[12] * m2.m[11];
    result.m[9]  = m1.m[1] * m2.m[8]  + m1.m[5] * m2.m[9]  + m1.m[9]  * m2.m[10] + m1.m[13] * m2.m[11];
    result.m[10] = m1.m[2] * m2.m[8]  + m1.m[6] * m2.m[9]  + m1.m[10] * m2.m[10] + m1.m[14] * m2.m[11];
    result.m[11] = m1.m[3] * m2.m[8]  + m1.m[7] * m2.m[9]  + m1.m[11] * m2.m[10] + m1.m[15] * m2.m[11];
    
    result.m[12] = m1.m[0] * m2.m[12] + m1.m[4] * m2.m[13] + m1.m[8]  * m2.m[14] + m1.m[12] * m2.m[15];
    result.m[13] = m1.m[1] * m2.m[12] + m1.m[5] * m2.m[13] + m1.m[9]  * m2.m[14] + m1.m[13] * m2.m[15];
    result.m[14] = m1.m[2] * m2.m[12] + m1.m[6] * m2.m[13] + m1.m[10] * m2.m[14] + m1.m[14] * m2.m[15];
    result.m[15] = m1.m[3] * m2.m[12] + m1.m[7] * m2.m[13] + m1.m[11] * m2.m[14] + m1.m[15] * m2.m[15];
    
    return result;
}


GSMatrix4 GSMatrix4_Translate(GLKVector3 v)
{
    GSMatrix4 matrix;
    
    matrix.m[0] = matrix.m[5] = matrix.m[10] = matrix.m[15] = 1.0;
    matrix.m[1] = matrix.m[2] = matrix.m[3]  = matrix.m[4]  = 0.0;
    matrix.m[6] = matrix.m[7] = matrix.m[8]  = matrix.m[9]  = 0.0;    
    matrix.m[11] = 0.0;
    matrix.m[12] = v.x;
    matrix.m[13] = v.y;
    matrix.m[14] = v.z;
    
    return matrix;
}


GSMatrix4 GSMatrix4_Scale(GLKVector3 v)
{
    GSMatrix4 matrix;
    
    matrix.m[1]  = matrix.m[2]  = matrix.m[3]  = matrix.m[4]  = 0.0;
    matrix.m[6]  = matrix.m[7]  = matrix.m[8]  = matrix.m[9]  = 0.0;
    matrix.m[11] = matrix.m[12] = matrix.m[13] = matrix.m[14] = 0.0;
    matrix.m[0]  = v.x;
    matrix.m[5]  = v.y;
    matrix.m[10] = v.z;
    matrix.m[15] = 1.0;
    
    return matrix;
}


GLKVector3 GSMatrix4_ProjVec3(GSMatrix4 m, GLKVector3 v)
{
    GLKVector3 result;
    
    result.x = v.x*m.m[0] + v.y*m.m[4] + v.z*m.m[8] + m.m[12];
    result.y = v.x*m.m[1] + v.y*m.m[5] + v.z*m.m[9] + m.m[13];
    result.z = v.x*m.m[2] + v.y*m.m[6] + v.z*m.m[10]+ m.m[14];
    
    return result;
}


GLKVector4 GSMatrix4_ProjVec4(GSMatrix4 m, GLKVector4 v)
{
    GLKVector4 result;
    
    result.x = v.x*m.m[0] + v.y*m.m[4] + v.z*m.m[8] + m.m[12];
    result.y = v.x*m.m[1] + v.y*m.m[5] + v.z*m.m[9] + m.m[13];
    result.z = v.x*m.m[2] + v.y*m.m[6] + v.z*m.m[10]+ m.m[14];
    result.w = v.x*m.m[3] + v.y*m.m[7] + v.z*m.m[11]+ m.m[15];
    
    return result;
}
