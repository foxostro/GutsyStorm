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
@class GSChunkStore;


@interface GSActiveRegion : NSObject

/* Constructor.
 *
 * Parameters:
 * activeRegionExtent -- Vector specifies the AABB of the active region. The camera position plus/minus this vector
 *                       equals the max/min corners of the AABB.
 * camera -- The camera at the center of the active region.
 * chunkStore -- Used to generate and retrieve VAOs.
 */
- (nonnull instancetype)initWithActiveRegionExtent:(vector_float3)activeRegionExtent
                                             camera:(nonnull GSCamera *)camera
                                        chunkStore:(nonnull GSChunkStore *)chunkStore;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (nonnull NSArray<GSBoxedVector *> *)pointsInCameraFrustum;

/* Accepts a block which modifies part of the active region. Ensures that the changes appear "instantly" from the
 * perspective of the display link thread.
 */
- (void)modifyWithBlock:(void (^ _Nonnull)(void))block;

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
