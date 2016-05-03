//
//  GSTerrainActiveRegion.h
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
@class GSTerrainChunkStore;


@interface GSTerrainActiveRegion : NSObject

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
                                        chunkStore:(nonnull GSTerrainChunkStore *)chunkstore;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

/* Instructs the active region to drop all items in the draw list in order to free up memory. */
- (void)clearDrawList;

- (void)draw;

- (nonnull NSArray<GSBoxedVector *> *)pointsInCameraFrustum;

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
