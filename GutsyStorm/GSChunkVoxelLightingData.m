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
#define INDEX2(x,y,z) ((size_t)(((x+1)*(CHUNK_SIZE_Y+2)*(CHUNK_SIZE_Z+2)) + ((y+1)*(CHUNK_SIZE_Z+2)) + (z+1)))


static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunkVoxelLightingData (Private)

- (BOOL)isAdjacentToSunlightAtPoint:(GSIntegerVector3)p lightLevel:(int)lightLevel;
- (BOOL)isSunlitAtPoint:(GSIntegerVector3)p neighbors:(GSChunkVoxelData **)neighbors;
- (float)getDistToSunlightAtPoint:(GSIntegerVector3)p neighbors:(GSChunkVoxelData **)neighbors;
- (void)generateLightingWithNeighbors:(GSChunkVoxelData **)chunks;

- (void)loadFromFile:(NSURL *)url;
- (void)saveToFileWithContainingFolder:(NSURL *)folder;

@end


@implementation GSChunkVoxelLightingData

+ (NSString *)fileNameFromMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.lighting.dat", minP.x, minP.y, minP.z];
}


- (id)initWithChunkAndNeighbors:(GSChunkVoxelData **)_chunks
						 folder:(NSURL *)folder
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
        sunlight = calloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z, sizeof(int));
		if(!sunlight) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for sunlight array."];
		}
		
		lockLightingData = [[NSConditionLock alloc] init];
		[lockLightingData setName:@"GSChunkVoxelLightingData.lockLightingData"];
		
		// chunks array is freed by th asynchronous task to fetch/load the lighting data
		GSChunkVoxelData **chunks = calloc(CHUNK_NUM_NEIGHBORS, sizeof(GSChunkVoxelData *));
		if(!chunks) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for temporary chunks array."];
		}
		
		for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
		{
			chunks[i] = _chunks[i];
			[chunks[i] retain];
		}
		
        // Fire off asynchronous task to generate chunk sunlight values.
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		dispatch_async(queue, ^{
			[lockLightingData lock];
			
			NSURL *url = [NSURL URLWithString:[GSChunkVoxelLightingData fileNameFromMinP:minP]
								relativeToURL:folder];
			
			if([url checkResourceIsReachableAndReturnError:NULL]) {
				// Load chunk from disk.
				[self loadFromFile:url];
			} else {
				// Generate chunk from scratch.
				[self generateLightingWithNeighbors:chunks];
				[self saveToFileWithContainingFolder:folder];
			}
			
			[lockLightingData unlockWithCondition:READY];
			
			// No longer need references to the neighboring chunks.
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


- (int)getSunlightAtPoint:(GSIntegerVector3)p assumeBlocksOutsideChunkAreDark:(BOOL)assumeBlocksOutsideChunkAreDark
{
	assert(sunlight);
	
	if(p.x < 0 || p.x >= CHUNK_SIZE_X || p.y < 0 || p.y >= CHUNK_SIZE_Y || p.z < 0 || p.z >= CHUNK_SIZE_Z) {
		if(!assumeBlocksOutsideChunkAreDark) {
			[NSException raise:NSInvalidArgumentException format:@"Specified block is outside of the chunk."];
		}
		
		return 0;
	}
	
	size_t idx = INDEX(p.x, p.y, p.z);
	assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return sunlight[idx];
}

@end


@implementation GSChunkVoxelLightingData (Private)

// Assumes the caller is already holding "lockVoxelData".
// Returns YES if any voxel adjacent to the specified voxel is lit to the specified light level or higher.
- (BOOL)isAdjacentToSunlightAtPoint:(GSIntegerVector3)p lightLevel:(int)lightLevel
{
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x, p.y+1, p.z) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x, p.y-1, p.z) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x-1, p.y, p.z) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x+1, p.y, p.z) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x, p.y, p.z-1) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	if([self getSunlightAtPoint:GSIntegerVector3_Make(p.x, p.y, p.z+1) assumeBlocksOutsideChunkAreDark:YES] >= lightLevel) {
		return YES;
	}
	
	return NO;
}


/* Returns YES if the block at the given position is directly sunlit (is outside).
 * Assumes the caller is already holding locks on all neighboring chunks.
 */
- (BOOL)isSunlitAtPoint:(GSIntegerVector3)p neighbors:(GSChunkVoxelData **)neighbors
{
	GSIntegerVector3 adjustedChunkLocalPos = {0};
	BOOL isSunlit = NO;
	
	GSChunkVoxelData *chunk = [GSChunkVoxelData getNeighborVoxelAtPoint:p
															  neighbors:neighbors
												 outRelativeToNeighborP:&adjustedChunkLocalPos];
	
	isSunlit = [chunk getPointerToVoxelAtPoint:adjustedChunkLocalPos]->outside;
	
	return isSunlit;
}


/* Gets the distance from the origin to the nearest sunlit block.
 * Assumes the caller is already holding locks on all neighboring chunks.
 */
- (float)getDistToSunlightAtPoint:(GSIntegerVector3)origin
					   neighbors:(GSChunkVoxelData **)neighbors
{
	if([self isSunlitAtPoint:origin neighbors:neighbors]) {
		return 0;
	}
	
	float nearestSunlight = INFINITY;
	GSIntegerVector3 p;
	
	for(p.x = origin.x - CHUNK_LIGHTING_MAX + 1; p.x < origin.x + CHUNK_LIGHTING_MAX; ++p.x)
    {
		for(p.y = MAX(0, origin.y - CHUNK_LIGHTING_MAX + 1); p.y < MIN(CHUNK_SIZE_Y, origin.y + CHUNK_LIGHTING_MAX); ++p.y)
        {
			for(p.z = origin.z - CHUNK_LIGHTING_MAX + 1; p.z < origin.z + CHUNK_LIGHTING_MAX; ++p.z)
            {
				if([self isSunlitAtPoint:p neighbors:neighbors]) {
					float dist = sqrtf(SQR(origin.x - p.x) + SQR(origin.y - p.y) + SQR(origin.z - p.z));
					nearestSunlight = MIN(nearestSunlight, dist);
				}
			}
		}
    }
	
	return nearestSunlight;
}


// Generates sunlight values for all blocks in the chunk.
- (void)generateLightingWithNeighbors:(GSChunkVoxelData **)chunks
{
	// Atomically, grab all the chunks relevant to lighting.
	[[GSChunkStore lockWhileLockingMultipleChunks] lock];
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData lockWhenCondition:READY];
	}
	[[GSChunkStore lockWhileLockingMultipleChunks] unlock];
	
	//CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
	
	// Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
	// Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
	// Set the blocks we find to the next lower light level.
	GSIntegerVector3 p;
	for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
	{
		for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
		{
			for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
			{
				size_t idx = INDEX(p.x, p.y, p.z);
				assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
				
				float dist = [self getDistToSunlightAtPoint:p neighbors:chunks];
				sunlight[idx] = MAX(CHUNK_LIGHTING_MAX - (int)dist, 0);
			}
		}
	}
	
	// Give up locks on the neighboring chunks.
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData unlockWithCondition:READY];
	}
	
	//CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
	//NSLog(@"Finished calculating sunlight for chunk. It took %.3fs", timeEnd - timeStart);
}


/* Returns YES if the chunk data is reachable on the filesystem and loading was successful.
 * Assumes the caller already holds "lockLightinData".
 */
- (void)loadFromFile:(NSURL *)url
{
	const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(int);
	
	// Read the contents of the file into "sunlight".
	NSData *data = [[NSData alloc] initWithContentsOfURL:url];
	if([data length] != len) {
		[NSException raise:@"Runtime Error"
					format:@"Unexpected length of data for chunk. Got %ul bytes. Expected %lu bytes.", [data length], len];
	}
	[data getBytes:sunlight length:len];
	[data release];
}


// Assumes the caller is already holding "lockLightinData".
- (void)saveToFileWithContainingFolder:(NSURL *)folder
{
	const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(int);
	
	NSURL *url = [NSURL URLWithString:[GSChunkVoxelLightingData fileNameFromMinP:minP]
						relativeToURL:folder];
	
	[[NSData dataWithBytes:sunlight length:len] writeToURL:url atomically:YES];
}

@end
