//
//  GSVector4.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/1/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_GSVector4_h
#define GutsyStorm_GSVector4_h

typedef struct
{
    float x, y, z, w;
} GSVector4;


GSVector4 GSVector4_Make(float x, float y, float z, float w);

#endif
