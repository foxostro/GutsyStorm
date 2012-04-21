//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSNoise.h"


#define INDEX(x,y,z) ((size_t)(((x)*CHUNK_SIZE_Y*CHUNK_SIZE_Z) + ((y)*CHUNK_SIZE_Z) + (z)))


static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunkVoxelData (Private)

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (void)saveToFileWithContainingFolder:(NSURL *)folder;
- (void)loadFromFile:(NSURL *)url;
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight;
- (void)recalcOutsideVoxelsNoLock;

@end


@implementation GSChunkVoxelData

+ (NSString *)fileNameFromMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}


/* Given a position relative to this voxel, and a list of neighboring chunks, return the chunk that contains the specified position.
 * also returns the position in the local coordinate system of that chunk.
 * The position must be contained in this chunk or any of the specified neighbors.
 */
+ (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3)chunkLocalP
									neighbors:(GSChunkVoxelData **)neighbors
					   outRelativeToNeighborP:(GSIntegerVector3 *)outRelativeToNeighborP
{
	assert(neighbors);
	assert(outRelativeToNeighborP);
	assert(chunkLocalP.y >= 0);
	assert(chunkLocalP.y < CHUNK_SIZE_Y);
	
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


- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)_minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder;
{
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.        
        assert(terrainHeight >= 0.0);
        
        lockVoxelData = [[NSConditionLock alloc] init];
		[lockVoxelData setName:@"GSChunkVoxelData.lockVoxelData"];
		
        voxelData = NULL;
		
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		// Fire off asynchronous task to generate voxel data.
        // When this finishes, the condition in lockVoxelData will be set to CONDITION_VOXEL_DATA_READY.
        dispatch_async(queue, ^{
			[lockVoxelData lock];
			
			NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameFromMinP:minP]
								relativeToURL:folder];
			
			[self allocateVoxelData];
			
			if([url checkResourceIsReachableAndReturnError:NULL]) {
				// Load chunk from disk.
				[self loadFromFile:url];
			} else {
				// Generate chunk from scratch.
				[self generateVoxelDataWithSeed:seed terrainHeight:terrainHeight];
				[self saveToFileWithContainingFolder:folder];
			}
			
			[lockVoxelData unlockWithCondition:READY];
        });
    }
    
    return self;
}


- (void)dealloc
{
    [lockVoxelData lock];
    [self destroyVoxelData];
    [lockVoxelData unlock];
    [lockVoxelData release];
    
	[super dealloc];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)getVoxelAtPoint:(GSIntegerVector3)p
{
	return *[self getPointerToVoxelAtPoint:p];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t *)getPointerToVoxelAtPoint:(GSIntegerVector3)p
{
	assert(voxelData);
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
	
	size_t idx = INDEX(p.x, p.y, p.z);
	assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return &voxelData[idx];
}

@end


@implementation GSChunkVoxelData (Private)


// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
	[self destroyVoxelData];
    
    voxelData = calloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z, sizeof(voxel_t));
    if(!voxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for chunk's voxelData"];
    }
}


// Assumes the caller is already holding "lockVoxelData".
- (void)destroyVoxelData
{
    free(voxelData);
    voxelData = NULL;
}


// Assumes the caller is already holding "lockVoxelData".
- (void)saveToFileWithContainingFolder:(NSURL *)folder
{
	const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
	
	NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameFromMinP:minP]
						relativeToURL:folder];
	
	[[NSData dataWithBytes:voxelData length:len] writeToURL:url atomically:YES];
}


// Assumes the caller is already holding "lockVoxelData".
- (void)recalcOutsideVoxelsNoLock
{
	// Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
	// We assume here that the chunk is the height of the world.
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
		for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
		{
			// Get the y value of the highest non-empty voxel in the chunk.
			ssize_t heightOfHighestVoxel;
			for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
			{
				GSIntegerVector3 p = {x, heightOfHighestVoxel, z};
				voxel_t *voxel = [self getPointerToVoxelAtPoint:p];
				
				if(!voxel->empty) {
					break;
				}
			}
			
			for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
			{
				GSIntegerVector3 p = {x, y, z};
				voxel_t *voxel = [self getPointerToVoxelAtPoint:p];
				voxel->outside = (y >= heightOfHighestVoxel);
			}
		}
    }
}


/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 *
 * Assumes the caller already holds "lockVoxelData".
 */
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
    GSNoise *noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
    GSNoise *noiseSource1 = [[GSNoise alloc] initWithSeed:(seed+1)];
    
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
                GSVector3 p = GSVector3_Add(GSVector3_Make(x, y, z), minP);
				voxel_t *voxel = [self getPointerToVoxelAtPoint:GSIntegerVector3_Make(x, y, z)];
				voxel->empty = !isGround(terrainHeight, noiseSource0, noiseSource1, p);
				voxel->outside = NO; // updated below
            }
        }
    }
    
    [noiseSource0 release];
    [noiseSource1 release];
	
	[self recalcOutsideVoxelsNoLock];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk voxel data. It took %.3fs", timeEnd - timeStart);
}


/* Returns YES if the chunk data is reachable on the filesystem and loading was successful.
 * Assumes the caller already holds "lockVoxelData".
 */
- (void)loadFromFile:(NSURL *)url
{
	const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
	
	// Read the contents of the file into "voxelData".
	NSData *data = [[NSData alloc] initWithContentsOfURL:url];
	if([data length] != len) {
		[NSException raise:@"Runtime Error"
					format:@"Unexpected length of data for chunk. Got %ul bytes. Expected %lu bytes.", [data length], len];
	}
	[data getBytes:voxelData length:len];
	[data release];
}

@end


// Return a value between -1 and +1 so that a line through the y-axis maps to a smooth gradient of values from -1 to +1.
static float groundGradient(float terrainHeight, GSVector3 p)
{
    const float y = p.y;
    
    if(y < 0.0) {
        return -1;
    } else if(y > terrainHeight) {
        return +1;
    } else {
        return 2.0*(y/terrainHeight) - 1.0;
    }
}


// Returns YES if the point is ground, NO otherwise.
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p)
{
	BOOL groundLayer = NO;
	BOOL floatingMountain = NO;
	BOOL test = NO;
	
	// Normal rolling hills
    {
		const float freqScale = 0.025;
		float n = [noiseSource0 getNoiseAtPoint:GSVector3_Scale(p, freqScale) numOctaves:4];
		float turbScaleX = 2.0;
		float turbScaleY = terrainHeight / 2.0;
		float yFreq = turbScaleX * ((n+1) / 2.0);
		float t = turbScaleY * [noiseSource1 getNoiseAtPoint:GSVector3_Make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
		groundLayer = groundGradient(terrainHeight, GSVector3_Make(p.x, p.y + t, p.z)) <= 0;
	}
	
	// For testing sunlight propagation
	{
		if(p.x > 80 && p.x < 100 && p.z > 100 && p.z < 120) {
			test = (p.y == 20) || (p.y == 22);
		}
	}
	
	// Giant floating mountain
	{
		/* The floating mountain is generated by starting with a sphere and applying turbulence to the surface.
		 * The upper hemisphere is also squashed to make the top flatter.
		 */
		
		GSVector3 mountainCenter = GSVector3_Make(50, 50, 80);
		GSVector3 toMountainCenter = GSVector3_Sub(mountainCenter, p);
		float distance = GSVector3_Length(toMountainCenter);
		float radius = 30.0;
		
		// Apply turbulence to the surface of the mountain.
		float freqScale = 0.70;
		float turbScale = 15.0;
		
		// Avoid generating noise when too far away from the center to matter.
		if(distance > 2.0*radius) {
			floatingMountain = NO;
		} else {
			// Convert the point into spherical coordinates relative to the center of the mountain.
			float azimuthalAngle = acosf(toMountainCenter.z / distance);
			float polarAngle = atan2f(toMountainCenter.y, toMountainCenter.x);
			
			float t = turbScale * [noiseSource0 getNoiseAtPoint:GSVector3_Make(azimuthalAngle * freqScale, polarAngle * freqScale, 0.0)
													 numOctaves:4];
			
			// Flatten the top.
			if(p.y > mountainCenter.y) {
				radius -= (p.y - mountainCenter.y) * 3;
			}
			
			floatingMountain = (distance+t) < radius;
		}
	}
	
	return groundLayer || test || floatingMountain;
}
