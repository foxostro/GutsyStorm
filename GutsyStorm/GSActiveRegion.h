//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSGridVBOs;


@interface GSActiveRegion : NSObject

/* Constructor.
 *
 * Parameters:
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector equals the
 *                       max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * gridVBOs -- Stores and produces VBOs on for the terrain.
 */
- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                          camera:(GSCamera *)camera
                        gridVBOs:(GSGridVBOs * )gridVBOs;

- (void)update;

- (void)draw;

- (void)enumeratePointsWithBlock:(void (^)(GLKVector3 p))block;

/* Give up all stored references to active region VBO objects. */
- (void)purge;

@end
