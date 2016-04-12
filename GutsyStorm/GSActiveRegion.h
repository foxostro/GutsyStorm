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
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector
 *                       equals the max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * gridVAO -- Used to generate and retrieve VAOs.
 */
- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                             camera:(nonnull GSCamera *)camera
                                            vaoGrid:(nonnull GSGridVAO *)gridVAO;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (nonnull NSArray<GSBoxedVector *> *)pointsInCameraFrustum;

/* Accepts a block which modifies part of the active region. Ensures that the changes appear "instantly" from the
 * perspective of the display link thread.
 * The block is expected to return a list of points corresponding to the chunks which were modified.
 * If asynchronous chunk invalidation is going to happen then those blocks should be added to the specified group.
 */
- (void)modifyWithGroup:(nonnull dispatch_group_t)group
                  block:(NSArray<GSBoxedVector *> * _Nonnull (^ _Nonnull)(dispatch_group_t _Nonnull group))block;

/* Call this to notify the active region that a VAO in the active region needs to be generated or regenerated.
 * To ensure that updates to the world will are made visible in a timely manner, call this immediately when a VAO, or
 * it's underlying terrain data, changes.
 */
- (void)needsChunkGeneration;

/* Drain the internal async queue and shut it down.
 * Give up all stored references to active region VAOs.
 */
- (void)shutdown;

@end
