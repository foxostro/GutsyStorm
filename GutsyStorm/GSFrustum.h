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
#import "GSVector3.h"
#import "GSPlane.h"


#define GS_FRUSTUM_OUTSIDE   (0)
#define GS_FRUSTUM_INTERSECT (1)
#define GS_FRUSTUM_INSIDE    (2)


@interface GSFrustum : NSObject
{
    GSPlane pl[6];
    GSVector3 ntl;
    GSVector3 ntr;
    GSVector3 nbl;
    GSVector3 nbr;
    GSVector3 ftl;
    GSVector3 ftr;
    GSVector3 fbl;
    GSVector3 fbr;
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
- (void)setCamDefWithCameraEye:(GSVector3)p cameraCenter:(GSVector3)l cameraUp:(GSVector3)u;
- (int)boxInFrustumWithBoxVertices:(GSVector3 *)vertices;
- (void)draw;

@end
