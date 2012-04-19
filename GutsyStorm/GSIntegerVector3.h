//
//  GSIntegerVector3.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSIntegerVector3_h
#define GutsyStorm_GSIntegerVector3_h

typedef struct
{
	ssize_t x, y, z;
} GSIntegerVector3;


static inline GSIntegerVector3 GSIntegerVector3_Make(ssize_t x, ssize_t y, ssize_t z)
{
	GSIntegerVector3 p = {x, y, z};
	return p;
}

#endif
