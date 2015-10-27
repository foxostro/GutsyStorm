//
//  GSFrustum.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//
// Based tutorial at:
// <http://zach.in.tu-clausthal.de/teaching/cg_literatur/lighthouse3d_view_frustum_culling/index.html>
//

#import <Foundation/Foundation.h>
#import "GSPlane.h"


enum
{
    FRUSTUM_OUTSIDE=0,
    FRUSTUM_INTERSECT,
    FRUSTUM_INSIDE
};


@interface GSFrustum : NSObject

- (void)setCamInternalsWithAngle:(float)angle ratio:(float)ratio nearD:(float)nearD farD:(float)farD;
- (void)setCamDefWithCameraEye:(vector_float3)p cameraCenter:(vector_float3)l cameraUp:(vector_float3)u;
- (int)boxInFrustumWithBoxVertices:(nonnull vector_float3 *)vertices;

@end
