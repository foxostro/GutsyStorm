//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSChunkVBOs;


@interface GSActiveRegion : NSObject

/* Constructor.
 *
 * Parameters:
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector equals the
 *                       max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * vboProducer -- This block may be invoked at any time to retrieve the GSChunkVBO for any point in space.
 *                The block may return NULL if no VBO has been generated for that point or if the call would block on a lock.
 */
- (instancetype)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                                    camera:(GSCamera *)camera
                               vboProducer:(GSChunkVBOs * (^)(GLKVector3 p))vboProducer;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (void)enumeratePointsWithBlock:(void (^)(GLKVector3 p))block;

/* Call this to notify the active region that a VBO in the active region has been updated. (replaced, invalidated, &c)
 * If this is not called immediately when a VBO has been replaced then updates to the world will not be visible until the next
 * automatic update occurs.
 */
- (void)notifyOfChangeInActiveRegionVBOs;

/* Give up all stored references to active region VBO objects. */
- (void)purge;

@end
