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
#import "GSBoxedVector.h"
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed;
- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (NSString *)getChunkIDWithMinP:(GSVector3)minP;
- (void)computeChunkVisibility;
- (void)computeActiveChunksWithNoPrioritization;
- (void)computeActiveChunksSortingByCameraDistance;
- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags;

@end


@implementation GSChunkStore

@synthesize activeRegionExtent;

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
		
        // Active region is bounded at y>=0.
        activeRegionExtent = GSVector3_Make(512, 704, 512);
        assert(fmodf(activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(activeRegionExtent.z, CHUNK_SIZE_Z) == 0);
        
		maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X) *
		                  (activeRegionExtent.y/CHUNK_SIZE_Y) *
		                  (2*activeRegionExtent.z/CHUNK_SIZE_Z);
        
		activeChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		tmpActiveChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		
        cache = [[NSCache alloc] init];
        [cache setCountLimit:2*maxActiveChunks];
		
        // Refresh the active chunks and compute initial chunk visibility.
		[self computeActiveChunksSortingByCameraDistance];
        [self computeChunkVisibility];
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
    
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
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


- (void)computeChunkVisibility
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();

    GSFrustum *frustum = [camera frustum];
    [frustum retain];
    
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunk *chunk = activeChunks[i];
        assert(chunk); // After the collection loop, above, activeChunks should be filled.
        chunk->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:chunk->corners]);
    }
    
    [frustum release];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


// Compute the active chunks without wasting time prioritizing by which chunks will be needed first.
- (void)computeActiveChunksWithNoPrioritization
{
    GSVector3 center = [camera cameraEye];
    
    const ssize_t activeRegionExtentX = activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = activeRegionExtent.y/CHUNK_SIZE_Y;
    
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
    for(ssize_t x = -activeRegionExtentX; x < activeRegionExtentX; ++x)
    {
        for(ssize_t y = 0; y < activeRegionSizeY; ++y)
        {
            for(ssize_t z = -activeRegionExtentZ; z < activeRegionExtentZ; ++z)
            {
                assert((x+activeRegionExtentX) >= 0);
                assert(x < activeRegionExtentX);
                assert((z+activeRegionExtentZ) >= 0);
                assert(z < activeRegionExtentZ);
                assert(y >= 0);
                assert(y < activeRegionSizeY);
                
                GSVector3 p = GSVector3_Make(center.x + x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, center.z + z*CHUNK_SIZE_Z);
                
                GSChunk *chunk = [self getChunkAtPoint:p];
                [chunk retain];
                
                size_t idx = ((x+activeRegionExtentX)*(activeRegionSizeY)*(2*activeRegionExtentZ)) +
                             (y*(2*activeRegionExtentZ)) +
                             (z+activeRegionExtentZ);
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


// Compute active chunks and take the time to ensure NEAR chunks come in before FAR chunks.
- (void)computeActiveChunksSortingByCameraDistance
{
    GSVector3 center = [camera cameraEye];
    
    const ssize_t activeRegionExtentX = activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = activeRegionExtent.y/CHUNK_SIZE_Y;
    
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
    
	// Get an unsorted list of the chunks which should be active.
	NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
    for(ssize_t x = -activeRegionExtentX; x < activeRegionExtentX; ++x)
    {
        for(ssize_t y = 0; y < activeRegionSizeY; ++y)
        {
            for(ssize_t z = -activeRegionExtentZ; z < activeRegionExtentZ; ++z)
            {
                assert((x+activeRegionExtentX) >= 0);
                assert(x < activeRegionExtentX);
                assert((z+activeRegionExtentZ) >= 0);
                assert(z < activeRegionExtentZ);
                assert(y >= 0);
                assert(y < activeRegionSizeY);
                
                GSVector3 p = GSVector3_Make(center.x + x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, center.z + z*CHUNK_SIZE_Z);
                
                GSBoxedVector *b = [[GSBoxedVector alloc] initWithVector:p];
                [unsortedChunks addObject:b];
                [b release];
            }
        }
    }
	
	// Sort by distance from the camera. Near chunks are first.
	NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(id a, id b) {
		GSVector3 centerA = [(GSBoxedVector *)a v];
		GSVector3 centerB = [(GSBoxedVector *)b v];
		float distA = GSVector3_Length(GSVector3_Sub(centerA, center));
		float distB = GSVector3_Length(GSVector3_Sub(centerB, center));
		return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
	}];
    
	[unsortedChunks release];
    
    // Fill the activeChunks array.
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSBoxedVector *b = (GSBoxedVector *)[sortedChunks objectAtIndex:i];
        
		GSChunk *chunk = [self getChunkAtPoint:[b v]];
        [chunk retain];
        activeChunks[i] = chunk;
    }
    
    // Release the temporary copy of the previous array.
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        [tmpActiveChunks[i] release];
        tmpActiveChunks[i] = nil;
    }
    
    [pool release];
}


- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
	if(!flags) {
		return; // nothing to do; existing active region is still valid.
	}
	
	// If the camera moved then recalculate the set of active chunks.
	if(flags & CAMERA_MOVED) {
		[self computeActiveChunksWithNoPrioritization];
        
	}
	
	// If the camera moved or turned then recalculate chunk visibility.
	if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        [self computeChunkVisibility];
	}
}

@end
