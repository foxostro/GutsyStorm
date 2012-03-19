//
//  GSVector3.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#include <math.h>
#include "GSVector3.h"


float EPSILON = 1e-8;


float GSVector3_Length(GSVector3 v)
{
	return sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
}


GSVector3 GSVector3_Normalize(GSVector3 v)
{
	GSVector3 normalized;
	float length;
	
	length = GSVector3_Length(v);
	normalized.x = v.x / length;
	normalized.y = v.y / length;
	normalized.z = v.z / length;
	
	return normalized;
}


GSVector3 GSVector3_Add(GSVector3 a, GSVector3 b)
{
	GSVector3 r;
	r.x = a.x + b.x;
	r.y = a.y + b.y;
	r.z = a.z + b.z;
	return r;
}


GSVector3 GSVector3_Sub(GSVector3 a, GSVector3 b)
{
	GSVector3 r;
	r.x = a.x - b.x;
	r.y = a.y - b.y;
	r.z = a.z - b.z;
	return r;
}


float GSVector3_Dot(GSVector3 a, GSVector3 b)
{
	return a.x*b.x + a.y*b.y + a.z*b.z;
}


GSVector3 GSVector3_Cross(GSVector3 a, GSVector3 b)
{
	GSVector3 r;
	r.x = a.y * b.z - a.z * b.y;
	r.y = a.z * b.x - a.x * b.z;
	r.z = a.x * b.y - a.y * b.x;
	return r;
}

int GSVector3_ToString(char * str, size_t len, GSVector3 v)
{
	return snprintf(str, len, "GSVector3(%.2f, %.2f, %.2f)", v.x, v.y, v.z);
}

int GSVector3_AreEqual(GSVector3 a, GSVector3 b)
{
	return fabsf(a.x-b.x)<EPSILON && fabsf(a.y-b.y)<EPSILON && fabsf(a.z-b.z)<EPSILON;
}

GSVector3 GSVector3_Scale(GSVector3 v, float scale)
{
	GSVector3 r;
	r.x = v.x*scale;
	r.y = v.y*scale;
	r.z = v.z*scale;
	return r;
}

GSVector3 GSVector3_Make(float x, float y, float z)
{
	GSVector3 r = {x, y, z};
	return r;
}