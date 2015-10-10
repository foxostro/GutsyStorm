//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSChunkVBOs;
@class GSGridVBOs;


@interface GSActiveRegion : NSObject

/* Constructor.
 *
 * Parameters:
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector equals the
 *                       max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * vboGrid -- Used to generate and retrieve VBOs.
 */
- (instancetype)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                                    camera:(GSCamera *)camera
                                   vboGrid:(GSGridVBOs *)gridVBOs;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (NSArray *)pointsInCameraFrustum;

/* Synchronously compute and update the set of VBOs that are in the camera frustum.
 * Unless you have are performing a latency sensitive operation, use -notifyOfChangeInActiveRegionVBOs instead.
 */
- (void)updateVBOsInCameraFrustum;

/* Call this to notify the active region that a VBO in the active region has been updated. (replaced, invalidated, &c)
 * If this is not called immediately when a VBO has been replaced then updates to the world will not be visible until
 * the next automatic update occurs.
 */
- (void)notifyOfChangeInActiveRegionVBOs;

/* Drain the internal async queue and shut it down.
 * Give up all stored references to active region VBO objects.
 */
- (void)shutdown;

@end
