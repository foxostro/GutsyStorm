//
//  GSChunkVoxelLightingData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/19/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelLightingData.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSNoise.h"


#define SQR(a) ((a)*(a))
#define INDEX(x,y,z) ((size_t)(((x)*(CHUNK_SIZE_Y)*(CHUNK_SIZE_Z)) + ((y)*(CHUNK_SIZE_Z)) + (z)))


static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunkVoxelLightingData (Private)

- (void)propagateSunlightAtPoint:(GSIntegerVector3)p neighbors:(GSChunkVoxelData **)neighbors;
- (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3)chunkLocalP
									neighbors:(GSChunkVoxelData **)neighbors
					   outRelativeToNeighborP:(GSIntegerVector3 *)outRelativeToNeighborP;

@end


@implementation GSChunkVoxelLightingData

@synthesize lockLightingData;


- (id)initWithChunkAndNeighbors:(GSChunkVoxelData **)_chunks
{
	assert(_chunks);
	assert(_chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
	assert(_chunks[CHUNK_NEIGHBOR_CENTER]);
	
    self = [super initWithMinP:_chunks[CHUNK_NEIGHBOR_CENTER].minP];
    if (self) {
        // Initialization code here.
		GSChunkVoxelData **chunks = calloc(CHUNK_NUM_NEIGHBORS, sizeof(GSChunkVoxelData *));
		if(!chunks) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for temporary chunks array."];
		}
		
		for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
		{
			chunks[i] = _chunks[i];
			[chunks[i] retain];
		}
		
        sunlight = calloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z, sizeof(unsigned));
		if(!sunlight) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for sunlight array."];
		}
		
		lockLightingData = [[NSConditionLock alloc] init];
		[lockLightingData setName:@"GSChunkVoxelLightingData.lockLightingData"];
		
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		// Fire off asynchronous task to generate chunk sunlight values.
        dispatch_async(queue, ^{
			[lockLightingData lock];
			[chunks[CHUNK_NEIGHBOR_CENTER].lockVoxelData lockWhenCondition:READY];
			CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
			
			for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
			{
				for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
				{
					for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
					{
						voxel_t *voxel = [chunks[CHUNK_NEIGHBOR_CENTER] getPointerToVoxelAtPoint:GSIntegerVector3_Make(x, y, z)];
						
						if(voxel->outside) {
							size_t idx = INDEX(x, y, z);
							assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
							sunlight[idx] = CHUNK_LIGHTING_MAX;
							//[self propagateSunlightAtPoint:p neighbors:(GSChunkVoxelData **)neighbors];
						}
					}
				}
			}
			
			CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
			NSLog(@"Finished calculating sunlight for chunk. It took %.3fs", timeEnd - timeStart);
			
			[chunks[CHUNK_NEIGHBOR_CENTER].lockVoxelData unlockWithCondition:READY];
			[lockLightingData unlockWithCondition:READY];
			
			for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
			{
				[chunks[i] release];
			}
			free(chunks);
        });
    }
    
    return self;
}


- (void)dealloc
{
    [lockLightingData lock];
    free(sunlight);
	sunlight = NULL;
    [lockLightingData unlock];
    [lockLightingData release];
    
	[super dealloc];
}


- (unsigned)getSunlightAtPoint:(GSIntegerVector3)p
{
	assert(sunlight);
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
	
	size_t idx = INDEX(p.x, p.y, p.z);
	assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return sunlight[idx];
}

@end


@implementation GSChunkVoxelData (Private)

/* Given a position relative to this voxel, and a list of neighboring chunks, return the chunk that contains the specified position.
 * also returns the position in the local coordinate system of that chunk.
 * The position must be contained in this chunk or any of the specified neighbors.
 */
- (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3)chunkLocalP
									neighbors:(GSChunkVoxelData **)neighbors
					   outRelativeToNeighborP:(GSIntegerVector3 *)outRelativeToNeighborP
{
	assert(neighbors);
	assert(outRelativeToNeighborP);
	
	(*outRelativeToNeighborP) = chunkLocalP;
	
	if(chunkLocalP.x >= CHUNK_SIZE_X) {
		outRelativeToNeighborP->x -= CHUNK_SIZE_X;
		
		if(chunkLocalP.z < 0) {
			outRelativeToNeighborP->z += CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_POS_X_NEG_Z];
		} else if(chunkLocalP.z >= CHUNK_SIZE_Z) {
			outRelativeToNeighborP->z -= CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_POS_X_POS_Z];
		} else {
			return neighbors[CHUNK_NEIGHBOR_POS_X_ZER_Z];
		}
	} else if(chunkLocalP.x < 0) {
		outRelativeToNeighborP->x += CHUNK_SIZE_X;
		
		if(chunkLocalP.z < 0) {
			outRelativeToNeighborP->z += CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_NEG_X_NEG_Z];
		} else if(chunkLocalP.z >= CHUNK_SIZE_Z) {
			outRelativeToNeighborP->z -= CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_NEG_X_POS_Z];
		} else {
			return neighbors[CHUNK_NEIGHBOR_NEG_X_ZER_Z];
		}
	} else {
		if(chunkLocalP.z < 0) {
			outRelativeToNeighborP->z += CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_ZER_X_NEG_Z];
		} else if(chunkLocalP.z >= CHUNK_SIZE_Z) {
			outRelativeToNeighborP->z -= CHUNK_SIZE_Z;
			return neighbors[CHUNK_NEIGHBOR_ZER_X_POS_Z];
		} else {
			return neighbors[CHUNK_NEIGHBOR_CENTER];
		}
	}
}


/* Propagates sunlight from chunks directly lit by the sun to surrounding chunks. This allows overhangs to have soft shadows.
 * Assumes the caller is already holding "lockVoxelData" for this chunk and all neighbors.
 */
- (void)propagateSunlightAtPoint:(GSIntegerVector3)origin
					   neighbors:(GSChunkVoxelData **)neighbors
{
#if 0
	GSIntegerVector3 p;
	
	for(p.x = origin.x - CHUNK_LIGHTING_MAX + 1; p.x < origin.x + CHUNK_LIGHTING_MAX; ++p.x)
    {
		for(p.y = MAX(0, origin.y - CHUNK_LIGHTING_MAX + 1); p.y < MIN(CHUNK_SIZE_Y, origin.y + CHUNK_LIGHTING_MAX); ++p.y)
        {
			for(p.z = origin.z - CHUNK_LIGHTING_MAX + 1; p.z < origin.z + CHUNK_LIGHTING_MAX; ++p.z)
            {
				GSIntegerVector3 adjustedChunkLocalPos = {0};
				
				GSChunkVoxelData *chunk = [self getNeighborVoxelAtPoint:p
															  neighbors:neighbors
												 outRelativeToNeighborP:&adjustedChunkLocalPos];
				
				if(chunk != self) {
					[chunk->lockVoxelData lockWhenCondition:READY];
				}
				
				voxel_t *voxel = [chunk getPointerToVoxelAtPoint:adjustedChunkLocalPos];
				
				if(voxel->outside) {
					voxel->sunlight = CHUNK_LIGHTING_MAX;
				} else {
					float dist = sqrtf(SQR(origin.x - p.x) + SQR(origin.y - p.y) + SQR(origin.z - p.z));
					voxel->sunlight = MAX((unsigned)dist, voxel->sunlight);
				}
				
				if(chunk != self) {
					[chunk->lockVoxelData unlockWithCondition:READY];
				}
			}
		}
    }
#endif
}

@end
