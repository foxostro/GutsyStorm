//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import <cache.h>
#import "GSRay.h"
#import "GSBoxedRay.h"
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed;
- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (NSString *)getChunkIDWithMinP:(GSVector3)minP;
- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags;

@end


@implementation GSChunkStore

- (id)initWithSeed:(unsigned)_seed camera:(GSCamera *)_camera
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
		terrainHeight = CHUNK_SIZE_Y;
		folder = [GSChunkStore createWorldSaveFolderWithSeed:seed];
		
        camera = _camera;
        [camera retain];
		
		feelerRays = [[NSMutableArray alloc] init];
		
        activeRegionExtent = GSVector3_Make(64, 64, 64);
		maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X) *
		                  (2*activeRegionExtent.y/CHUNK_SIZE_Y) *
		                  (2*activeRegionExtent.z/CHUNK_SIZE_Z);
		activeChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		tmpActiveChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		
        cache = [[NSCache alloc] init];
		
		[self recalculateActiveChunksWithCameraModifiedFlags:(CAMERA_MOVED | CAMERA_TURNED)];
    }
    
    return self;
}


- (void)dealloc
{
    [cache release];
    [camera release];
	[folder release];
	[feelerRays release];
	
	for(size_t i = 0; i < maxActiveChunks; ++i)
	{
		[activeChunks[i] release];
		activeChunks[i] = nil;
		
		[tmpActiveChunks[i] release];
		tmpActiveChunks[i] = nil;
	}
	
	free(activeChunks);
	free(tmpActiveChunks);
}


- (void)drawWithShader:(GSShader *)shader
{
	[shader bind];
	
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	
	for(size_t i = 0; i < maxActiveChunks; ++i)
	{
		GSChunk *chunk = activeChunks[i];
		if(chunk && chunk->visible) {
			[chunk draw];
		}
	}
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
	
    [shader unbind];
}


- (void)drawFeelerRays
{
	glDisable(GL_LIGHTING);
	glDisable(GL_TEXTURE_2D);
	glBegin(GL_LINES);
	
	NSEnumerator *e = [feelerRays objectEnumerator];
	id object;
	while(nil != (object = [e nextObject]))
	{
		GSBoxedRay *r = (GSBoxedRay *)object;
		
		glVertex3f(r.ray.origin.x, r.ray.origin.y, r.ray.origin.z);
		glVertex3f(r.ray.origin.x + r.ray.direction.x,
				   r.ray.origin.y + r.ray.direction.y,
				   r.ray.origin.z + r.ray.direction.z);
	}
	
	glEnd();
	glEnable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
	if(flags) {
		[self recalculateActiveChunksWithCameraModifiedFlags:flags];
	}
}


- (GSChunk *)getChunkAtPoint:(GSVector3)p
{
    GSChunk *chunk = nil;
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    NSString *chunkID = [self getChunkIDWithMinP:minP];
    
    chunk = [cache objectForKey:chunkID];
    if(!chunk) {
        /*char buffer[64] = {0};
        GSVector3_ToString(buffer, sizeof(buffer), minP);
        NSLog(@"Need to fetch another chunk; chunkID=%@, minP=%s", chunkID, buffer);*/
        
        chunk = [[[GSChunk alloc] initWithSeed:seed
                                          minP:minP
								 terrainHeight:terrainHeight
										folder:folder] autorelease];
        [cache setObject:chunk forKey:chunkID];
    }
	
	[chunkID release];
    
    return chunk;
}


- (GSChunk *)rayCastToFindChunk:(GSRay)ray intersectionDistanceOut:(float *)intersectionDistanceOut
{
	// Get a list of the active chunks whose AABB are in the path of the ray.
	NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
	for(size_t i = 0; i < maxActiveChunks; ++i)
	{
		float distance = INFINITY;
		GSChunk *chunk = activeChunks[i];
		
		if(!chunk) {
			continue;
		}
		
		if(GSRay_IntersectsAABB(ray, [chunk minP], [chunk maxP], &distance)) {
			[unsortedChunks addObject:chunk];
		}
	}
	
	// Sort by distance from the camera. Near chunks are first.
	GSVector3 cameraEye = [camera cameraEye];
	NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(id a, id b) {
		GSChunk *chunkA = (GSChunk *)a;
		GSChunk *chunkB = (GSChunk *)b;
		GSVector3 centerA = GSVector3_Scale(GSVector3_Add([chunkA minP], [chunkA maxP]), 0.5);
		GSVector3 centerB = GSVector3_Scale(GSVector3_Add([chunkB minP], [chunkB maxP]), 0.5);
		float distA = GSVector3_Length(GSVector3_Sub(centerA, cameraEye));
		float distB = GSVector3_Length(GSVector3_Sub(centerB, cameraEye));;
		return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
	}];
	
	// For all chunks in the path of the array, determine whether the ray actually hits a voxel in the chunk.
	float nearestDistance = INFINITY;
	GSChunk *nearestChunk = nil;
	NSEnumerator *e = [sortedChunks objectEnumerator];
	id object;
	while(nil != (object = [e nextObject]))
	{
		float distance = INFINITY;
		GSChunk *chunk = (GSChunk *)object;
		
		if([chunk rayHitsChunk:ray intersectionDistanceOut:&distance]) {
			if(distance < nearestDistance) {
				nearestDistance = distance;
				nearestChunk = chunk;
			}
		}
	}
	
	// Return the distance to the intersection, if requested.
	if(nearestChunk && intersectionDistanceOut) {
		*intersectionDistanceOut = nearestDistance;
	}
	
	[unsortedChunks release];
	
	return nearestChunk;
}

@end


@implementation GSChunkStore (Private)

+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
    folder = [folder stringByAppendingPathComponent:@"GutsyStorm"];
	folder = [folder stringByAppendingPathComponent:@"save"];
	folder = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",seed]];
	NSLog(@"ChunkStore will save chunks to folder: %@", folder);
	
	if(![[NSFileManager defaultManager] createDirectoryAtPath:folder
								  withIntermediateDirectories:YES
												   attributes:nil
														error:NULL]) {
		NSLog(@"Failed to create save folder: %@", folder);
	}
	
	NSURL *url = [[NSURL alloc] initFileURLWithPath:folder isDirectory:YES];
	
	if(![url checkResourceIsReachableAndReturnError:NULL]) {
		NSLog(@"ChunkStore's Save folder not reachable: %@", folder);
	}
	
	return url;
}

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}


- (NSString *)getChunkIDWithMinP:(GSVector3)minP
{
	return [[NSString alloc] initWithFormat:@"%.0f_%.0f_%.0f", minP.x, minP.y, minP.z];
}


- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
	if(!flags) {
		return; // nothing to do; existing active region is still valid.
	}
	
	// If the camera moved then recalculate the set of active chunks.
	if(flags & CAMERA_MOVED) {
		GSVector3 minP = GSVector3_Sub([camera cameraEye], activeRegionExtent);
		
		const size_t activeRegionSizeX = 2*activeRegionExtent.x/CHUNK_SIZE_X;
		const size_t activeRegionSizeY = 2*activeRegionExtent.y/CHUNK_SIZE_Y;
		const size_t activeRegionSizeZ = 2*activeRegionExtent.z/CHUNK_SIZE_Z;
		
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		// Copy the activeChunks array and retain each chunk. This prevents chunks from being deallocated when we do
		// releaseActiveChunks, which can prevent eviction of chunks which were in the active region and will remain in the active
		// region.
		for(size_t i = 0; i < maxActiveChunks; ++i)
		{
			GSChunk *chunk = activeChunks[i];
			tmpActiveChunks[i] = chunk;
			
			if(chunk) {
				[chunk retain];
				
				// Also, reset the chunk visibility check. We'll recalculate a bit later.
				chunk->visible = NO;
			}
		}
		
		// Release all the chunks and reset the activeChunks array.
		for(size_t i = 0; i < maxActiveChunks; ++i)
		{
			[activeChunks[i] release];
			activeChunks[i] = nil;
		}
		
		// Collect all chunks that fall within the active region.
		for(size_t x = 0; x < activeRegionSizeX; ++x)
		{
			for(size_t y = 0; y < activeRegionSizeY; ++y)
			{
				for(size_t z = 0; z < activeRegionSizeZ; ++z)
				{
					GSVector3 p = GSVector3_Add(minP, GSVector3_Make(x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, z*CHUNK_SIZE_Z));
					
					GSChunk *chunk = [self getChunkAtPoint:p];
					[chunk retain];
					
					size_t idx = (x*activeRegionSizeY*activeRegionSizeZ) + (y*activeRegionSizeZ) + z;
					assert(idx < maxActiveChunks);
					activeChunks[idx] = chunk;
				}
			}
		}
		
		// Release the temporary copy of the previous array.
		for(size_t i = 0; i < maxActiveChunks; ++i)
		{
			[tmpActiveChunks[i] release];
			tmpActiveChunks[i] = nil;
		}
		
		[pool release];
	}
	
	// If the camera moved or turned then recalculate chunk visibility.
	if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
		//CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
		
		GSFrustum *frustum = [camera frustum];
		[frustum retain];
		for(size_t i = 0; i < maxActiveChunks; ++i)
		{
			GSChunk *chunk = activeChunks[i];
			chunk->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:chunk->corners]);
		}
		[frustum release];
		
		//CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
		//NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
	}
}

@end
