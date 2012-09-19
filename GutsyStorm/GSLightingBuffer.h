//
//  GSLightingBuffer.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSReaderWriterLock.h"
#import "GSNeighborhood.h"
#import "Voxel.h"

// A chunk-sized buffer of lighting values. For example, the lighting contribution, per block, of direct sunlight.
@interface GSLightingBuffer : NSObject
{
 @public
    GSReaderWriterLock *lockLightingBuffer;
    uint8_t *lightingBuffer;
}

@property (readonly, nonatomic) GSReaderWriterLock *lockLightingBuffer;
@property (readonly, nonatomic) uint8_t *lightingBuffer;

/* Obtains a reader lock on the skylight data and allows the caller to access it in the specified block. */
- (void)readerAccessToBufferUsingBlock:(void (^)(void))block;

/* Obtains a writer lock on the skylight data and allows the caller to access it in the specified block. */
- (void)writerAccessToBufferUsingBlock:(void (^)(void))block;

/* Returns the skylight value for the specified point that was calculated earlier.
 * Assumes the caller is already holding "lockSkylight".
 */
- (uint8_t)lightAtPoint:(GSIntegerVector3)chunkLocalP;

/* Returns a pointer to the skylight value for the specified point that was calculated earlier.
 * Assumes the caller is already holding "lockSkylight".
 */
- (uint8_t *)pointerToLightAtPoint:(GSIntegerVector3)chunkLocalP;

/* Gets a smooth skylight lighting value by interpolating block skylight values around the specified point.
 * Assumes the caller is already holding "lockSkylight" on all neighbors and "lockVoxelData" on self, at least.
 */
- (void)interpolateLightAtPoint:(GSIntegerVector3)p
                         neighbors:(GSNeighborhood *)neighbors
                       outLighting:(block_lighting_t *)lighting;

@end
