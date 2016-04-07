//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <simd/vector.h>

@class GSCamera;
@class GSChunkVAO;
@class GSGridVAO;
@class GSBoxedVector;


@interface GSActiveRegion : NSObject

/* Constructor.
 *
 * Parameters:
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector equals the
 *                       max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * gridVAO -- Used to generate and retrieve VAOs.
 */
- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                             camera:(nonnull GSCamera *)camera
                                            vaoGrid:(nonnull GSGridVAO *)gridVAO;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (nonnull NSArray<GSBoxedVector *> *)pointsInCameraFrustum;

/* Synchronously compute and update the set of VAOs that are in the camera frustum.
 * Unless you have are performing a latency sensitive operation, use -notifyOfChangeInActiveRegionVAOs instead.
 */
- (void)updateVAOsInCameraFrustum;

/* Call this to notify the active region that a VAO in the active region has been updated. (replaced, invalidated, &c)
 * If this is not called immediately when a VAO has been replaced then updates to the world will not be visible until
 * the next automatic update occurs.
 */
- (void)notifyOfChangeInActiveRegionVAOs;

/* Drain the internal async queue and shut it down.
 * Give up all stored references to active region VAOs.
 */
- (void)shutdown;

@end
