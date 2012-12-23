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
    GLKVector3 ntl;
    GLKVector3 ntr;
    GLKVector3 nbl;
    GLKVector3 nbr;
    GLKVector3 ftl;
    GLKVector3 ftr;
    GLKVector3 fbl;
    GLKVector3 fbr;
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
- (void)setCamDefWithCameraEye:(GLKVector3)p cameraCenter:(GLKVector3)l cameraUp:(GLKVector3)u;
- (int)boxInFrustumWithBoxVertices:(GLKVector3 *)vertices;
- (void)draw;

@end
