//
//  GSFrustum.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//
// Based tutorial at:
// <http://zach.in.tu-clausthal.de/teaching/cg_literatur/lighthouse3d_view_frustum_culling/index.html>
//

#import <Foundation/Foundation.h>
#import "GSPlane.h"


#define GS_FRUSTUM_OUTSIDE   (0)
#define GS_FRUSTUM_INTERSECT (1)
#define GS_FRUSTUM_INSIDE    (2)


@interface GSFrustum : NSObject
{
    GSPlane pl[6];
    vector_float3 ntl;
    vector_float3 ntr;
    vector_float3 nbl;
    vector_float3 nbr;
    vector_float3 ftl;
    vector_float3 ftr;
    vector_float3 fbl;
    vector_float3 fbr;
    float nearD;
    float farD;
    float ratio;
    float angle;
    float tang;
    float nw;
    float nh;
    float fw;
    float fh;
}

- (void)setCamInternalsWithAngle:(float)angle ratio:(float)ratio nearD:(float)nearD farD:(float)farD;
- (void)setCamDefWithCameraEye:(vector_float3)p cameraCenter:(vector_float3)l cameraUp:(vector_float3)u;
- (int)boxInFrustumWithBoxVertices:(vector_float3 *)vertices;
- (void)draw;

@end
