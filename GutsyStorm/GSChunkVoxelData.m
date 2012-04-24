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


#define SQR(a) ((a)*(a))
#define INDEX(x,y,z) ((size_t)(((x)*CHUNK_SIZE_Y*CHUNK_SIZE_Z) + ((y)*CHUNK_SIZE_Z) + (z)))


static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunkVoxelData (Private)

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (void)saveVoxelDataToFileWithContainingFolder:(NSURL *)folder;
- (void)loadVoxelDataFromFile:(NSURL *)url;
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight;
- (void)recalcOutsideVoxelsNoLock;

- (void)countNeighborsForAmbientOcclusionsAtPoint:(GSIntegerVector3)p
										neighbors:(GSChunkVoxelData **)chunks
							  outAmbientOcclusion:(ambient_occlusion_t*)ao;
- (void)generateAmbientOcclusionWithNeighbors:(GSChunkVoxelData **)chunks;

- (BOOL)isAdjacentToSunlightAtPoint:(GSIntegerVector3)p lightLevel:(int)lightLevel neighbors:(GSChunkVoxelData **)neighbors;
- (void)generateSunlightWithNeighbors:(GSChunkVoxelData **)chunks;

@end


@implementation GSChunkVoxelData

+ (NSString *)fileNameForVoxelDataFromMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
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
        
        lockVoxelData = [[GSReaderWriterLock alloc] init];
		[lockVoxelData lockForWriting]; // This is locked initially and unlocked at the end of the first update.
		
		lockSunlight = [[NSConditionLock alloc] init];
		[lockSunlight setName:@"GSChunkVoxelData.lockSunlight"];
		
		lockAmbientOcclusion = [[NSConditionLock alloc] init];
		[lockAmbientOcclusion setName:@"GSChunkVoxelData.lockAmbientOcclusion"];
		
        voxelData = NULL;
		
		sunlight = calloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z, sizeof(int));
		if(!sunlight) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for sunlight array."];
		}
		
		ambientOcclusion = calloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z, sizeof(ambient_occlusion_t));
		if(!ambientOcclusion) {
			[NSException raise:@"Out of Memory" format:@"Failed to allocate memory for ambientOcclusion array."];
		}
		
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		// Fire off asynchronous task to generate voxel data.
        // When this finishes, the condition in lockVoxelData will be set to CONDITION_VOXEL_DATA_READY.
        dispatch_async(queue, ^{
			NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:minP]
								relativeToURL:folder];
			
			[self allocateVoxelData];
			
			if([url checkResourceIsReachableAndReturnError:NULL]) {
				// Load chunk from disk.
				[self loadVoxelDataFromFile:url];
			} else {
				// Generate chunk from scratch.
				[self generateVoxelDataWithSeed:seed terrainHeight:terrainHeight];
				[self saveVoxelDataToFileWithContainingFolder:folder];
			}
			
			[lockVoxelData unlockForWriting];
        });
    }
    
    return self;
}


- (void)dealloc
{
    [lockVoxelData lockForWriting];
    [self destroyVoxelData];
    [lockVoxelData unlockForWriting];
    [lockVoxelData release];
	
    [lockSunlight lock];
    free(sunlight);
	sunlight = NULL;
    [lockSunlight unlock];
    [lockSunlight release];
	
    [lockAmbientOcclusion lock];
    free(ambientOcclusion);
	ambientOcclusion = NULL;
    [lockAmbientOcclusion unlock];
    [lockAmbientOcclusion release];
    
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


- (void)updateLightingWithNeighbors:(GSChunkVoxelData **)_chunks
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
		[self generateSunlightWithNeighbors:chunks];
		[self generateAmbientOcclusionWithNeighbors:chunks];
		
		// No longer need references to the neighboring chunks.
		for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
		{
			[chunks[i] release];
		}
		free(chunks);
	});
}


// Assumes the caller is already holding "lockSunlight".
- (int)getSunlightAtPoint:(GSIntegerVector3)p
{
	assert(sunlight);
	assert(p.x >= 0 && p.x < CHUNK_SIZE_X && p.y >= 0 && p.y < CHUNK_SIZE_Y && p.z >= 0 && p.z < CHUNK_SIZE_Z);
	
	size_t idx = INDEX(p.x, p.y, p.z);
	assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return sunlight[idx];
}


// Assumes the caller is already holding "lockAmbientOcclusion".
- (ambient_occlusion_t)getAmbientOcclusionAtPoint:(GSIntegerVector3)p
{
	assert(ambientOcclusion);
	assert(p.x >= 0 && p.x < CHUNK_SIZE_X && p.y >= 0 && p.y < CHUNK_SIZE_Y && p.z >= 0 && p.z < CHUNK_SIZE_Z);
	
	size_t idx = INDEX(p.x, p.y, p.z);
	assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return ambientOcclusion[idx];	
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
- (void)saveVoxelDataToFileWithContainingFolder:(NSURL *)folder
{
	const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
	
	NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:minP]
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
- (void)loadVoxelDataFromFile:(NSURL *)url
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


/* Assumes the caller is already holding "lockVoxelData".
 * Returns YES if any of the adjacent blocks is an empty block lit to the specified light level.
 * That is, light affects all cells, but only propagates through empty cells.
 */
- (BOOL)isAdjacentToSunlightAtPoint:(GSIntegerVector3)p
						 lightLevel:(int)lightLevel
						  neighbors:(GSChunkVoxelData **)neighbors
{
	if(p.y+1 >= CHUNK_SIZE_Y) {
		return YES;
	} else {
		GSIntegerVector3 up    = GSIntegerVector3_Make(p.x, p.y+1, p.z);
		GSIntegerVector3 adjustedUp = {0};
		GSChunkVoxelData *chunkUp = getNeighborVoxelAtPoint(up, neighbors, &adjustedUp);
		
		if([chunkUp getVoxelAtPoint:adjustedUp].empty && [chunkUp getSunlightAtPoint:adjustedUp] == lightLevel) {
			return YES;
		}
	}
	
	if(p.y-1 >= 0) {
		GSIntegerVector3 down  = GSIntegerVector3_Make(p.x, p.y-1, p.z);
		GSIntegerVector3 adjustedDown = {0};
		GSChunkVoxelData *chunkDown = getNeighborVoxelAtPoint(down, neighbors, &adjustedDown);
		
		if([chunkDown getVoxelAtPoint:adjustedDown].empty && [chunkDown getSunlightAtPoint:adjustedDown] == lightLevel) {
			return YES;
		}
	}
	
	GSIntegerVector3 dir[4] = {
		GSIntegerVector3_Make(p.x-1, p.y, p.z),
		GSIntegerVector3_Make(p.x+1, p.y, p.z),
		GSIntegerVector3_Make(p.x, p.y, p.z-1),
		GSIntegerVector3_Make(p.x, p.y, p.z+1)
	};
	
	for(size_t i = 0; i < 4; ++i)
	{
		GSIntegerVector3 adjustedDir = {0};
		GSChunkVoxelData *adjustedChunk = getNeighborVoxelAtPoint(dir[i], neighbors, &adjustedDir);
		
		if([adjustedChunk getVoxelAtPoint:adjustedDir].empty &&
		   [adjustedChunk getSunlightAtPoint:adjustedDir] == lightLevel) {
			return YES;
		}
	}
	
	return NO;
}


// Generates sunlight values for all blocks in the chunk.
- (void)generateSunlightWithNeighbors:(GSChunkVoxelData **)chunks
{
	GSIntegerVector3 p = {0};
	
	[lockSunlight lock];
	
	// Atomically, grab all the chunks relevant to lighting.
	[[GSChunkStore lockWhileLockingMultipleChunks] lock];
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData lockForReading];
	}
	[[GSChunkStore lockWhileLockingMultipleChunks] unlock];
	
	//CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
	
	// Reset all empty, outside blocks to full sunlight.
	for(int i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
		{
			for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
			{
				for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
				{
					size_t idx = INDEX(p.x, p.y, p.z);
					assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));	
					
					if(chunks[i]->voxelData[idx].outside) {
						chunks[i]->sunlight[idx] = CHUNK_LIGHTING_MAX;
					}
				}
			}
		}
	}
	
	// Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
	// Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
	// Set the blocks we find to the next lower light level.
	for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
	{
		for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
		{
			for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
			{
				for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
				{
					size_t idx = INDEX(p.x, p.y, p.z);
					assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));	
					
					if((sunlight[idx] < lightLevel) && [self isAdjacentToSunlightAtPoint:p
																			  lightLevel:lightLevel
																			   neighbors:chunks]) {
						sunlight[idx] = MAX(sunlight[idx], lightLevel - 1);
					}
				}
			}
		}
	}
	
	// Give up locks on the neighboring chunks.
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData unlockForReading];
	}
	
	[lockSunlight unlockWithCondition:READY];
	
	//CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
	//NSLog(@"Finished calculating sunlight for chunk. It took %.3fs", timeEnd - timeStart);
}


- (void)countNeighborsForAmbientOcclusionsAtPoint:(GSIntegerVector3)p
										neighbors:(GSChunkVoxelData **)chunks
							  outAmbientOcclusion:(ambient_occlusion_t*)ao
{
	/* Front is in the -Z direction and back is the +Z direction.
	 * This is a totally arbitrary convention.
	 */
	
	// If the block is empty then bail out early. The point p is always within the chunk.
	if(voxelData[INDEX(p.x, p.y, p.z)].empty) {
		ao->ftr = 0.0;
		ao->ftl = 0.0;
		ao->fbr = 0.0;
		ao->fbl = 0.0;
		ao->btr = 0.0;
		ao->btl = 0.0;
		ao->bbr = 0.0;
		ao->bbl = 0.0;
		
		return;
	}
	
	// Common subexpressions are factored out to reduce the number of neighbor checks.
	const BOOL e1  = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y,   p.z-1), chunks);
	const BOOL e2  = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y+1, p.z)  , chunks);
	const BOOL e3  = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y+1, p.z-1), chunks);
	const BOOL e4  = isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y,   p.z)  , chunks);
	const BOOL e5  = isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y,   p.z-1), chunks);
	const BOOL e6  = isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y+1, p.z)  , chunks);
	const BOOL e7  = isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y,   p.z)  , chunks);
	const BOOL e8  = isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y,   p.z-1), chunks);
	const BOOL e9  = isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y+1, p.z)  , chunks);
	const BOOL e10 = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y-1, p.z)  , chunks);
	const BOOL e11 = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y-1, p.z-1), chunks);
	const BOOL e12 = isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y-1, p.z)  , chunks);
	const BOOL e13 = isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y-1, p.z)  , chunks);
	const BOOL e14 = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y,   p.z+1), chunks);
	const BOOL e15 = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y+1, p.z+1), chunks);
	const BOOL e16 = isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y,   p.z+1), chunks);
	const BOOL e17 = isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y,   p.z+1), chunks);
	const BOOL e18 = isEmptyAtPoint(GSIntegerVector3_Make(p.x,   p.y-1, p.z+1), chunks);
	
	const float a = 1.0 / 7.0; // vertex brightness conferred by each additional empty neighbor

	// front, top, right
	ao->ftr =  e1 ? a : 0.0;
	ao->ftr += e2 ? a : 0.0;
	ao->ftr += e3 ? a : 0.0;
	ao->ftr += e4 ? a : 0.0;
	ao->ftr += e5 ? a : 0.0;
	ao->ftr += e6 ? a : 0.0;
	ao->ftr += isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y+1, p.z-1), chunks) ? a : 0.0;
	
	// front, top, left
	ao->ftl =  e1 ? a : 0.0;
	ao->ftl += e2 ? a : 0.0;
	ao->ftl += e3 ? a : 0.0;
	ao->ftl += e7 ? a : 0.0;
	ao->ftl += e8 ? a : 0.0;
	ao->ftl += e9 ? a : 0.0;
	ao->ftl += isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y+1, p.z-1), chunks) ? a : 0.0;
	
	// front, bottom, right
	ao->fbr =  e1 ? a : 0.0;
	ao->fbr += e10 ? a : 0.0;
	ao->fbr += e11 ? a : 0.0;
	ao->fbr += e4 ? a : 0.0;
	ao->fbr += e5 ? a : 0.0;
	ao->fbr += e12 ? a : 0.0;
	ao->fbr += isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y-1, p.z-1), chunks) ? a : 0.0;
	
	// front, bottom, left
	ao->fbl =  e1 ? a : 0.0;
	ao->fbl += e10 ? a : 0.0;
	ao->fbl += e11 ? a : 0.0;
	ao->fbl += e7 ? a : 0.0;
	ao->fbl += e8 ? a : 0.0;
	ao->fbl += e13 ? a : 0.0;
	ao->fbl += isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y-1, p.z-1), chunks) ? a : 0.0;
	
	// back, top, right
	ao->btr =  e14 ? a : 0.0;
	ao->btr += e2 ? a : 0.0;
	ao->btr += e15 ? a : 0.0;
	ao->btr += e4 ? a : 0.0;
	ao->btr += e16 ? a : 0.0;
	ao->btr += e6 ? a : 0.0;
	ao->btr += isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y+1, p.z+1), chunks) ? a : 0.0;
	
	// back, top, left
	ao->btl =  e14 ? a : 0.0;
	ao->btl += e2 ? a : 0.0;
	ao->btl += e15 ? a : 0.0;
	ao->btl += e7 ? a : 0.0;
	ao->btl += e17 ? a : 0.0;
	ao->btl += e9 ? a : 0.0;
	ao->btl += isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y+1, p.z+1), chunks) ? a : 0.0;
	
	// back, bottom, right
	ao->bbr =  e14 ? a : 0.0;
	ao->bbr += e10 ? a : 0.0;
	ao->bbr += e18 ? a : 0.0;
	ao->bbr += e4 ? a : 0.0;
	ao->bbr += e16 ? a : 0.0;
	ao->bbr += e12 ? a : 0.0;
	ao->bbr += isEmptyAtPoint(GSIntegerVector3_Make(p.x+1, p.y-1, p.z+1), chunks) ? a : 0.0;
	
	// back, bottom, left
	ao->bbl =  e14 ? a : 0.0;
	ao->bbl += e10 ? a : 0.0;
	ao->bbl += e18 ? a : 0.0;
	ao->bbl += e7 ? a : 0.0;
	ao->bbl += e17 ? a : 0.0;
	ao->bbl += e13 ? a : 0.0;
	ao->bbl += isEmptyAtPoint(GSIntegerVector3_Make(p.x-1, p.y-1, p.z+1), chunks) ? a : 0.0;
}


// Generates ambient occlusion values for all blocks in the chunk.
- (void)generateAmbientOcclusionWithNeighbors:(GSChunkVoxelData **)chunks
{
	GSIntegerVector3 p = {0};
	
	[lockAmbientOcclusion lock];
    
	CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
	
	// Atomically, grab all the chunks relevant to lighting.
	// Needs to be atomic to avoid deadlock.
	[[GSChunkStore lockWhileLockingMultipleChunks] lock];
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData lockForReading];
	}
	[[GSChunkStore lockWhileLockingMultipleChunks] unlock];
	
	// Count the empty neighbors of each vertex in the block.
	for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
	{
		for(p.x = 0; p.x < CHUNK_SIZE_X; ++p.x)
		{
			for(p.y = 0; p.y < CHUNK_SIZE_Y; ++p.y)
			{
				for(p.z = 0; p.z < CHUNK_SIZE_Z; ++p.z)
				{
					size_t idx = INDEX(p.x, p.y, p.z);
					[self countNeighborsForAmbientOcclusionsAtPoint:p
														  neighbors:chunks
												outAmbientOcclusion:&ambientOcclusion[idx]];
				}
			}
		}
	}
	
	// Give up locks on the neighboring chunks.
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData unlockForReading];
	}
	
    CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"Finished generating chunk ambient occlusion. It took %.3fs", timeEnd - timeStart);
	
	[lockAmbientOcclusion unlockWithCondition:READY];
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


/* Given a position relative to this voxel, and a list of neighboring chunks, return the chunk that contains the specified position.
 * also returns the position in the local coordinate system of that chunk.
 * The position must be contained in this chunk or any of the specified neighbors.
 */
GSChunkVoxelData* getNeighborVoxelAtPoint(GSIntegerVector3 chunkLocalP,
										  GSChunkVoxelData **neighbors,
										  GSIntegerVector3 *outRelativeToNeighborP)
{
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


/* Assumes the caller is already holding "lockVoxelData" on all neighbors.
 * Returns YES if the specified block is empty.
 */
BOOL isEmptyAtPoint(GSIntegerVector3 p, GSChunkVoxelData **neighbors)
{
	// Assumes each chunk spans the entire vertical extent of the world.
	
	if(p.y < 0) {
		return NO; // Space below the world is always full.
	}
	
	if(p.y >= CHUNK_SIZE_Y) {
		return YES; // Space above the world is always empty.
	}
	
	GSIntegerVector3 adjustedPos = {0};
	GSChunkVoxelData *chunk = getNeighborVoxelAtPoint(p, neighbors, &adjustedPos);
	
    return chunk->voxelData[INDEX(adjustedPos.x, adjustedPos.y, adjustedPos.z)].empty;
}
