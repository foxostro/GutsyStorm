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
 * vboPrefetcher -- This block may be invoked at any time to notify the VBO source of the active region's intentions to retrieve the
 *                  corresponding GSChunkVBO for that point sometime soon. The VBO source (the details of which are unimportant to
 *                  this class) may decide to act on this information by beginning VBO generation now.
 */
- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                          camera:(GSCamera *)camera
                     vboProducer:(GSChunkVBOs * (^)(GLKVector3 p))vboProducer
                   vboPrefetcher:(void (^)(GLKVector3 p))vboPrefetcher;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (void)enumeratePointsWithBlock:(void (^)(GLKVector3 p))block;

@end
