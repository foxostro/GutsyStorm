//
//  GSPlane.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <simd/simd.h>

typedef struct
{
    vector_float3 p, n;
} GSPlane;

float GSPlaneDistance(GSPlane plane, vector_float3 r);
GSPlane GSPlaneMake(vector_float3 p0, vector_float3 p1, vector_float3 p2);
