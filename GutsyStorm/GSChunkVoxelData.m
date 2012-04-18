//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkVoxelData.h"
#import "GSNoise.h"


#define SQR(a) ((a)*(a))
#define INDEX(x,y,z) ((size_t)(((x+1)*(CHUNK_SIZE_Y+2)*(CHUNK_SIZE_Z+2)) + ((y+1)*(CHUNK_SIZE_Z+2)) + (z+1)))


static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunkVoxelData (Private)

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight;
- (BOOL)areAnyAdjacentVoxelsOutsideAndEmptyWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z;
- (void)recalcOutsideVoxelsNoLock;
- (void)propagateSunlightWithX:(ssize_t)thisX y:(ssize_t)thisY z:(ssize_t)thisZ;
- (void)recalcLightingNoLock;

@end


@implementation GSChunkVoxelData

@synthesize lockVoxelData;


+ (NSString *)computeChunkFileNameWithMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.chunk", minP.x, minP.y, minP.z];
}


- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)_minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder
{
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.        
        assert(terrainHeight >= 0.0);
        
        lockVoxelData = [[NSConditionLock alloc] init];
        voxelData = NULL;
        
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		// Fire off asynchronous task to generate voxel data.
        // When this finishes, the condition in lockVoxelData will be set to CONDITION_VOXEL_DATA_READY.
        dispatch_async(queue, ^{
			NSURL *url = [NSURL URLWithString:[GSChunkVoxelData computeChunkFileNameWithMinP:minP]
								relativeToURL:folder];
			
			if([url checkResourceIsReachableAndReturnError:NULL]) {
				// Load chunk from disk.
				[self loadFromFile:url];
			} else {
				// Generate chunk from scratch.
				[self generateVoxelDataWithSeed:seed terrainHeight:terrainHeight];
				[self saveToFileWithContainingFolder:folder];
			}
        });
    }
    
    return self;
}


- (void)saveToFileWithContainingFolder:(NSURL *)folder
{
	const size_t len = (CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2) * sizeof(voxel_t);
	
	NSURL *url = [NSURL URLWithString:[GSChunkVoxelData computeChunkFileNameWithMinP:minP]
						relativeToURL:folder];
	
	[lockVoxelData lockWhenCondition:CONDITION_VOXEL_DATA_READY];
	[[NSData dataWithBytes:voxelData length:len] writeToURL:url atomically:YES];
	[lockVoxelData unlock];
}


// Returns YES if the chunk data is reachable on the filesystem and loading was successful.
- (void)loadFromFile:(NSURL *)url
{
	const size_t len = (CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2) * sizeof(voxel_t);
	
	[lockVoxelData lock];
    [self allocateVoxelData];
	
	// Read the contents of the file into "voxelData".
	NSData *data = [[NSData alloc] initWithContentsOfURL:url];
	if([data length] != len) {
		[NSException raise:@"Runtime Error"
					format:@"Unexpected length of data for chunk. Got %ul bytes. Expected %lu bytes.", [data length], len];
	}
	[data getBytes:voxelData length:len];
	[data release];
    
	[self recalcOutsideVoxelsNoLock];
	[self recalcLightingNoLock];
	
	[lockVoxelData unlockWithCondition:CONDITION_VOXEL_DATA_READY];
}


- (void)dealloc
{
    [lockVoxelData lock];
    [self destroyVoxelData];
    [lockVoxelData unlock];
    [lockVoxelData release];
    
	[super dealloc];
}


- (BOOL)rayHitsChunk:(GSRay)ray intersectionDistanceOut:(float *)intersectionDistanceOut
{
	// Test the ray against the chunk's overall AABB. This rejects rays early if they don't go anywhere near a voxel.
	if(!GSRay_IntersectsAABB(ray, minP, maxP, NULL)) {
		return NO;
	}
	
	// Test the ray against the AABB for each voxel in the chunk.
	// XXX: Could reduce the number of intersection tests with a spatial data structure such as an octtree.
	GSVector3 pos;
	for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                GSVector3 voxelMinP = GSVector3_Sub(pos, GSVector3_Make(0.5, 0.5, 0.5));
                GSVector3 voxelMaxP = GSVector3_Add(pos, GSVector3_Make(0.5, 0.5, 0.5));
				
				if(GSRay_IntersectsAABB(ray, voxelMinP, voxelMaxP, intersectionDistanceOut)) {
					return YES;
				}
            }
        }
    }
	
	return NO;
}


- (voxel_t)getVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z
{
	assert(x >= -1 && x < CHUNK_SIZE_X+1);
    assert(y >= -1 && y < CHUNK_SIZE_Y+1);
    assert(z >= -1 && z < CHUNK_SIZE_Z+1);
	
	size_t idx = INDEX(x, y, z);
	assert(idx >= 0 && idx < ((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2)));
    
    return voxelData[idx];
}


// Assumes the caller is already holding "lockVoxelData".
- (voxel_t *)getPointerToVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z
{
    assert(x >= -1 && x < CHUNK_SIZE_X+1);
    assert(y >= -1 && y < CHUNK_SIZE_Y+1);
    assert(z >= -1 && z < CHUNK_SIZE_Z+1);
	
	size_t idx = INDEX(x, y, z);
	assert(idx >= 0 && idx < ((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2)));
    
    return &voxelData[idx];
}


@end


@implementation GSChunkVoxelData (Private)


// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
	[self destroyVoxelData];
    
    voxelData = calloc((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2), sizeof(voxel_t));
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
// Returns YES if any voxel adjacent to the specified voxel is empty and outside.
- (BOOL)areAnyAdjacentVoxelsOutsideAndEmptyWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z
{
	voxel_t *up = [self getPointerToVoxelValueWithX:x y:y+1 z:z];
	if(up->empty && up->outside) {
		return YES;
	}
	
	voxel_t *down = [self getPointerToVoxelValueWithX:x y:y-1 z:z];
	if(down->empty && down->outside) {
		return YES;
	}
	
	voxel_t *left = [self getPointerToVoxelValueWithX:x-1 y:y z:z];
	if(left->empty && left->outside) {
		return YES;
	}
	
	voxel_t *right = [self getPointerToVoxelValueWithX:x+1 y:y z:z];
	if(right->empty && right->outside) {
		return YES;
	}
	
	voxel_t *front = [self getPointerToVoxelValueWithX:x y:y z:z-1];
	if(front->empty && front->outside) {
		return YES;
	}
	
	voxel_t *back = [self getPointerToVoxelValueWithX:x y:y z:z+1];
	if(back->empty && back->outside) {
		return YES;
	}
	
	return NO;
}


// Assumes the caller is already holding "lockVoxelData".
- (void)recalcOutsideVoxelsNoLock
{
	// Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
	// We assume here that the chunk is the height of the world.
    for(ssize_t x = -1; x < CHUNK_SIZE_X+1; ++x)
    {
		for(ssize_t z = -1; z < CHUNK_SIZE_Z+1; ++z)
		{
			// Get the y value of the highest non-empty voxel in the chunk.
			ssize_t heightOfHighestVoxel;
			for(heightOfHighestVoxel = CHUNK_SIZE_Y; heightOfHighestVoxel >= -1; --heightOfHighestVoxel)
			{
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:heightOfHighestVoxel z:z];
				
				if(!voxel->empty) {
					break;
				}
			}
			
			for(ssize_t y = -1; y < CHUNK_SIZE_Y+1; ++y)
			{
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				voxel->outside = (y >= heightOfHighestVoxel);
			}
		}
    }
    
	// Solid voxels which are directly adjacent to an empty, outside voxel are also considered to be outside.
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				voxel->outside = voxel->outside || (!voxel->empty && [self areAnyAdjacentVoxelsOutsideAndEmptyWithX:x y:y z:z]);
			}
		}
    }
}


// Assumes the caller is already holding "lockVoxelData".
- (void)propagateSunlightWithX:(ssize_t)thisX y:(ssize_t)thisY z:(ssize_t)thisZ
{	
	for(ssize_t x = MAX(0, thisX - CHUNK_LIGHTING_MAX/2); x < MIN(CHUNK_SIZE_X, thisX + CHUNK_LIGHTING_MAX/2); ++x)
    {
		for(ssize_t y = MAX(0, thisY - CHUNK_LIGHTING_MAX/2); y < MIN(CHUNK_SIZE_Y, thisY + CHUNK_LIGHTING_MAX/2); ++y)
        {
			for(ssize_t z = MAX(0, thisZ - CHUNK_LIGHTING_MAX/2); z < MIN(CHUNK_SIZE_Z, thisZ + CHUNK_LIGHTING_MAX/2); ++z)
            {
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				
				if(voxel->outside) {
					voxel->sunlight = CHUNK_LIGHTING_MAX;
				} else {
					float dist = sqrtf(SQR(thisX-x) + SQR(thisY-y) + SQR(thisZ-z));
					voxel->sunlight = MAX((unsigned)dist, voxel->sunlight);
				}
			}
		}
    }
}


// Assumes the caller is already holding "lockVoxelData".
- (void)recalcLightingNoLock
{
	/* TODO: For each outside block, do a flood-fill in the chunk to populate lighting values.
	 * Do note that this will be inaccurate across chunk boundaries.
	 */
	
	CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
	// Reset sunlight
    for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				voxel->sunlight = 0;
			}
		}
    }
	
	for(ssize_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(ssize_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(ssize_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				
				if(voxel->outside) {
					[self propagateSunlightWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z];
				}
			}
		}
    }
	
    CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"Finished calculating chunk lighting. It took %.3fs", timeEnd - timeStart);
}


/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight
{
    CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
    [lockVoxelData lock];
    
    [self allocateVoxelData];
    
    GSNoise *noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
    GSNoise *noiseSource1 = [[GSNoise alloc] initWithSeed:(seed+1)];
    
    for(ssize_t x = -1; x < CHUNK_SIZE_X+1; ++x)
    {
        for(ssize_t y = -1; y < CHUNK_SIZE_Y+1; ++y)
        {
            for(ssize_t z = -1; z < CHUNK_SIZE_Z+1; ++z)
            {
                GSVector3 p = GSVector3_Add(GSVector3_Make(x, y, z), minP);
				voxel_t *voxel = [self getPointerToVoxelValueWithX:x y:y z:z];
				voxel->empty = !isGround(terrainHeight, noiseSource0, noiseSource1, p);
				voxel->outside = NO; // updated later
				voxel->sunlight = 0; // updated later
            }
        }
    }
    
    [noiseSource0 release];
    [noiseSource1 release];
    
	[self recalcOutsideVoxelsNoLock];
	[self recalcLightingNoLock];
    
    CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"Finished generating chunk voxel data. It took %.3fs", timeEnd - timeStart);
    [lockVoxelData unlockWithCondition:CONDITION_VOXEL_DATA_READY];
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
	BOOL floatingMountain1 = NO;
	BOOL floatingMountain2 = NO;
	
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
	
	// Giant floating mountain (1)
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
			floatingMountain1 = NO;
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
			
			floatingMountain1 = (distance+t) < radius;
		}
	}
	
	return groundLayer || floatingMountain1 || floatingMountain2;
}
