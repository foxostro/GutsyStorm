//
//  GSVector4.c
//  GutsyStorm
//
//  Created by Andrew Fox on 4/1/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#include "GSVector4.h"


GSVector4 GSVector4_Make(float x, float y, float z, float w)
{
	GSVector4 r = {x, y, z, w};
	return r;
}