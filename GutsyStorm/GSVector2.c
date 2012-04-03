//
//  GSVector2.c
//  GutsyStorm
//
//  Created by Andrew Fox on 4/2/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#include "GSVector2.h"


GSVector2 GSVector2_Make(float x, float y)
{
	GSVector2 r = {x, y};
	return r;
}
