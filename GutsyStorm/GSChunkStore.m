//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import <cache.h>
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (NSString *)getChunkIDWithMinP:(GSVector3)minP;
- (void)recalculateActiveChunks;

@end


@implementation GSChunkStore

- (id)initWithSeed:(unsigned)_seed camera:(GSCamera *)_camera
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
		terrainHeight = CHUNK_SIZE_Y;
		folder = [[NSURL alloc] initFileURLWithPath:@"/tmp" isDirectory:YES];
		
        camera = _camera;
        [camera retain];
		
        activeRegionExtent = GSVector3_Make(128, terrainHeight/2.0, 128);
		maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X) *
		                  (2*activeRegionExtent.y/CHUNK_SIZE_Y) *
		                  (2*activeRegionExtent.z/CHUNK_SIZE_Z);
		activeChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		tmpActiveChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		
        cache = [[NSCache alloc] init];	
		
		[self recalculateActiveChunks];
    }
    
    return self;
}


- (void)dealloc
{
    [cache release];
    [camera release];
	[folder release];
	
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


- (void)draw
{
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
}


- (void)updateWithDeltaTime:(float)dt wasCameraModified:(BOOL)wasCameraModified
{
	if(wasCameraModified) {
		[self recalculateActiveChunks];
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

@end


@implementation GSChunkStore (Private)

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


- (void)recalculateActiveChunks
{
	GSVector3 minP = GSVector3_Sub([camera cameraEye], activeRegionExtent);
    GSFrustum *frustum = [camera frustum];
	
	const size_t activeRegionSizeX = 2*activeRegionExtent.x/CHUNK_SIZE_X;
	const size_t activeRegionSizeZ = 2*activeRegionExtent.z/CHUNK_SIZE_Z;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Copy the activeChunks array and retain each chunk. This prevents chunks from being deallocated when we do
	// releaseActiveChunks, which can prevent eviction of chunks which were in the active region and will remain in the active
	// region.
	for(size_t i = 0; i < maxActiveChunks; ++i)
	{
		GSChunk *chunk = activeChunks[i];
		[chunk retain];
		tmpActiveChunks[i] = chunk;
	}
	
	// Release all the chunks and reset the activeChunks array.
	for(size_t i = 0; i < maxActiveChunks; ++i)
	{
		[activeChunks[i] release];
		activeChunks[i] = nil;
	}
    
    // Draw all visible chunks that fall within the active region.
	for(size_t x = 0; x < activeRegionSizeX; ++x)
    {
        for(size_t z = 0; z < activeRegionSizeZ; ++z)
        {
			GSVector3 p = GSVector3_Add(minP, GSVector3_Make(x*CHUNK_SIZE_X, terrainHeight/2.0, z*CHUNK_SIZE_Z));
			
			GSChunk *chunk = [self getChunkAtPoint:p];
			[chunk retain];
			
            chunk->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:chunk->corners]);
			
			size_t idx = (activeRegionSizeX)*z + x;
			assert(idx < maxActiveChunks);
			activeChunks[idx] = chunk;
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

@end
