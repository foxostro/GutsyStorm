//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <OpenGL/glu.h>
#import <assert.h>
#import <cache.h>
#import "GSRay.h"
#import "GSBoxedRay.h"
#import "GSBoxedVector.h"
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

+ (NSURL *)createWorldSaveFolderWithSeed:(unsigned)seed;
- (void)drawFeelerRays;

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (GSVector3)computeChunkCenterForPoint:(GSVector3)p;
- (NSString *)getChunkIDWithMinP:(GSVector3)minP;

- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock;
- (void)computeChunkVisibility;
- (void)computeActiveChunks:(BOOL)sorted;
- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags;

- (void)deallocChunksWithArray:(GSChunk **)array len:(size_t)len;


- (NSArray *)sortPointsByDistFromCamera:(NSMutableArray *)unsortedPoints;
- (NSArray *)sortChunksByDistFromCamera:(NSMutableArray *)unsortedChunks;

- (GSVector3)getLookVecForCubeMapFace:(unsigned)face;
- (GSVector3)getUpVecForCubeMapFace:(unsigned)face;

@end


@implementation GSChunkStore

@synthesize activeRegionExtent;

- (id)initWithSeed:(unsigned)_seed camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
      skyboxShader:(GSShader *)_skyboxShader
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
		terrainHeight = 64.0;
		folder = [GSChunkStore createWorldSaveFolderWithSeed:seed];
		
        camera = _camera;
        [camera retain];
        
        terrainShader = _terrainShader;
        [terrainShader retain];
        
        skyboxShader = _skyboxShader;
        [skyboxShader retain];
		
		feelerRays = [[NSMutableArray alloc] init];
		
        // Active region is bounded at y>=0.
        activeRegionExtent = GSVector3_Make(512, 512, 512);
        assert(fmodf(activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(activeRegionExtent.z, CHUNK_SIZE_Z) == 0);
        
		maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X) *
		                  (activeRegionExtent.y/CHUNK_SIZE_Y) *
		                  (2*activeRegionExtent.z/CHUNK_SIZE_Z);
        
        activeChunks = calloc(maxActiveChunks, sizeof(GSChunk *));
		
        cache = [[NSCache alloc] init];
        [cache setCountLimit:2*maxActiveChunks];
        
		// Set up the skybox.
		NSRect bounds = NSMakeRect(0, 0, 512, 512);
        skybox = [[GSCube alloc] init];
        skyboxCubemap = [[GSRenderTexture alloc] initWithDimensions:bounds isCubeMap:YES];
		faceForNextUpdate = 0;
		
		// LOD regions should overlap a bit to hide the seams between them.
		foregroundRegionSize  =  96.0; // 0.0 to 96.0
		backgroundRegionSize1 =  64.0; // 64.0 to 288.0
		backgroundRegionSize2 = 256.0; // 256.0 and up
		
		for(unsigned i = 0; i < 6; ++i)
		{
			GSVector3 eye = [camera cameraEye];
			GSVector3 center = GSVector3_Add(eye, [self getLookVecForCubeMapFace:i]);
			GSVector3 up = [self getUpVecForCubeMapFace:i];
			
			GSCamera *c = [[GSCamera alloc] init];
			[c reshapeWithBounds:bounds
							 fov:90.0
						   nearD:backgroundRegionSize1
							farD:MIN(MIN(activeRegionExtent.x, activeRegionExtent.z), activeRegionExtent.y)];
			[c lookAt:eye center:center up:up];
			skyboxCamera[i] = c;
		}
		
        // Refresh the active chunks and compute initial chunk visibility.
		[self computeActiveChunks:YES];
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
    [terrainShader release];
    
    [skybox release];
    [skyboxShader release];
    [skyboxCubemap release];
	for(size_t i = 0; i < 6; ++i)
	{
		[skyboxCamera[i] release];
	}
       
    [self deallocChunksWithArray:activeChunks len:maxActiveChunks];
}


- (void)updateSkybox
{
    GSVector3 eye = [camera cameraEye];
    GSVector3 b = [self computeChunkCenterForPoint:eye];
    GLfloat lightDir[] = {0.707, -0.707, -0.707, 0.0};
    
	[terrainShader bind];
	
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    const float fov = 90.0;
    const float nearD = backgroundRegionSize1;
    const float farD = MIN(MIN(activeRegionExtent.x, activeRegionExtent.z), activeRegionExtent.y);
    glLoadIdentity();
	gluPerspective(fov, 1.0, nearD, farD);
    
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    
    // Set the camera for this face
    GSVector3 center = GSVector3_Add(eye, [self getLookVecForCubeMapFace:faceForNextUpdate]);
    GSVector3 up = [self getUpVecForCubeMapFace:faceForNextUpdate];
    glLoadIdentity();
    gluLookAt(eye.x, eye.y, eye.z,
              center.x, center.y, center.z,
              up.x, up.y, up.z);    
	
	// Set light direction. This must be done right after setting the camera transformation.
	// TODO: Set the light positions for real. We don't really know the scene's real light direction.
	glLightfv(GL_LIGHT0, GL_POSITION, lightDir);
	
	[skyboxCubemap startRenderForCubeFace:faceForNextUpdate];
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	
	// Draw all chunks.
	// TODO: Cull against the frustum for this face's camera.
	[self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
        if(!((p.x-b.x) >= -backgroundRegionSize1 && (p.x-b.x) <= backgroundRegionSize1 && (p.z-b.z) >= -backgroundRegionSize1 && (p.z-b.z) <= backgroundRegionSize1)) {
			GSChunk *chunk = [self getChunkAtPoint:p];
			if(1) { //if(GS_FRUSTUM_OUTSIDE != [[faceCamera frustum] boxInFrustumWithBoxVertices:chunk->corners]) {
				[chunk draw];
			}
		}
	 }];
	
	[skyboxCubemap finishRender];

    glPopMatrix(); // camera
    
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
	
    [terrainShader unbind];
	
	faceForNextUpdate = (faceForNextUpdate+1) % 6;
}


- (void)drawSkybox
{
	// Skybox textures are oriented along world-space axes, so rotate the box with the camera.
	glPushMatrix();
	gluLookAt(0, 0, 0,
              [camera cameraCenter].x - [camera cameraEye].x, [camera cameraCenter].y - [camera cameraEye].y, [camera cameraCenter].z - [camera cameraEye].z,
              [camera cameraUp].x,     [camera cameraUp].y,     [camera cameraUp].z);
	
    glPushAttrib(GL_ENABLE_BIT);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glDisable(GL_BLEND);
    glFrontFace(GL_CW); // we are inside the cube, so reverse the face winding direction
	[skyboxShader bind];
    [skybox draw];
    [skyboxShader unbind];
    glFrontFace(GL_CCW); // reset to OpenGL defaults
    glPopAttrib();
	
	glPopMatrix();
}


- (void)drawChunks
{
	[terrainShader bind];
	
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunk *chunk = activeChunks[i];
        assert(chunk);
        
        if(chunk->visible) {
			[chunk draw];
		}
    }
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
	
    [terrainShader unbind];
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
	[self recalculateActiveChunksWithCameraModifiedFlags:flags];
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
        GSChunk *chunk = activeChunks[i];
        assert(chunk);
        
        if(GSRay_IntersectsAABB(ray, [chunk minP], [chunk maxP], NULL)) {
            [unsortedChunks addObject:chunk];
        }
    }
	
	// Sort by distance from the camera. Near chunks are first.
    NSArray *sortedChunks = [self sortChunksByDistFromCamera: unsortedChunks]; // is autorelease

	// For all chunks in the path of the array, determine whether the ray actually hits a voxel in the chunk.
	float nearestDistance = INFINITY;
	GSChunk *nearestChunk = nil;
    for(GSChunk *chunk in sortedChunks)
    {
		float distance = INFINITY;
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


- (GSVector3)getUpVecForCubeMapFace:(unsigned)face
{
    GSVector3 up = GSVector3_Make(0, 0, 0);
    
    switch(face)
    {
        case CUBE_MAP_POSITIVE_X:
        case CUBE_MAP_NEGATIVE_X:
        case CUBE_MAP_POSITIVE_Z:
        case CUBE_MAP_NEGATIVE_Z:
            up.y = +1;
            break;
            
        case CUBE_MAP_POSITIVE_Y:
            up.z = +1;
            break;
            
        case CUBE_MAP_NEGATIVE_Y:
            up.z = -1;
            break;
    }
    
    return up;
}

- (GSVector3)getLookVecForCubeMapFace:(unsigned)face
{
    GSVector3 look = GSVector3_Make(0, 0, 0);
    
    switch(face)
    {
        case CUBE_MAP_POSITIVE_X:
            look.x = +1;
            break;
            
        case CUBE_MAP_NEGATIVE_X:
            look.x = -1;
            break;
            
        case CUBE_MAP_POSITIVE_Y:
            look.y = +1;
            break;
            
        case CUBE_MAP_NEGATIVE_Y:
            look.y = -1;
            break;
            
        case CUBE_MAP_POSITIVE_Z:
            look.z = +1;
            break;
            
        case CUBE_MAP_NEGATIVE_Z:
            look.z = -1;
            break;
    }
    
    return look;
}


- (void)deallocChunksWithArray:(GSChunk **)array len:(size_t)len
{
    for(size_t i = 0; i < len; ++i)
    {
        [array[i] release];
        array[i] = nil;
    }
    free(array);
}


- (NSArray *)sortChunksByDistFromCamera:(NSMutableArray *)unsortedChunks
{    
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
    
    return sortedChunks;
}


- (NSArray *)sortPointsByDistFromCamera:(NSMutableArray *)unsortedPoints
{
    GSVector3 center = [camera cameraEye];
    
    return [unsortedPoints sortedArrayUsingComparator: ^(id a, id b) {
        GSVector3 centerA = [(GSBoxedVector *)a v];
        GSVector3 centerB = [(GSBoxedVector *)b v];
        float distA = GSVector3_Length(GSVector3_Sub(centerA, center));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, center));
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
}


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


- (GSVector3)computeChunkCenterForPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
}


- (NSString *)getChunkIDWithMinP:(GSVector3)minP
{
	return [[NSString alloc] initWithFormat:@"%.0f_%.0f_%.0f", minP.x, minP.y, minP.z];
}


- (void)computeChunkVisibility
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();

	GSVector3 eye = [camera cameraEye];
    GSVector3 b = [self computeChunkCenterForPoint:eye];
    GSFrustum *frustum = [camera frustum];
    
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunk *chunk = activeChunks[i];
        assert(chunk);
        
        GSVector3 p = GSVector3_Scale(GSVector3_Add([chunk minP], [chunk maxP]), 0.5f); // TODO: precalculate chunk center point
        
		// Exclude chunks which are not in the foreground region (a portion of the active region).
        if((p.x-b.x) >= -foregroundRegionSize && (p.x-b.x) <= foregroundRegionSize &&
		   (p.z-b.z) >= -foregroundRegionSize && (p.z-b.z) <= foregroundRegionSize) {
            chunk->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:chunk->corners]);
        } else {
            chunk->visible = NO;
        }
    }
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


- (void)enumeratePointsInActiveRegionUsingBlock:(void (^)(GSVector3))myBlock
{
    const GSVector3 center = [camera cameraEye];
    const ssize_t activeRegionExtentX = activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = activeRegionExtent.y/CHUNK_SIZE_Y;

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
                
                GSVector3 p1 = GSVector3_Make(center.x + x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, center.z + z*CHUNK_SIZE_Z);
				
				GSVector3 p2 = [self computeChunkCenterForPoint:p1];
                
                myBlock(p2);
            }
        }
    }
}


// Compute active chunks and take the time to ensure NEAR chunks come in before FAR chunks.
- (void)computeActiveChunks:(BOOL)sorted
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    // Copy the activeChunks array to retain all chunks. This prevents chunks from being deallocated when we do
    // are in the process of selecting the new set of active chunks. This, in turn, can prevent eviction of chunks which were in
    // the active region and will remain in the active region.
    // Also, reset visibility computation on all active chunks. We'll recalculate a bit later.
    NSMutableArray *tmpActiveChunks = [[NSMutableArray alloc] initWithCapacity:maxActiveChunks];
    for(size_t i = 0; i < maxActiveChunks; ++i)
    {
        GSChunk *chunk = activeChunks[i];
        
        if(chunk) {
            chunk->visible = NO;
            [tmpActiveChunks addObject:chunk];
            [chunk release];
        }
    }
    
    if(sorted) {
        NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
        
        [self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
            GSBoxedVector *b = [[GSBoxedVector alloc] initWithVector:p];
            [unsortedChunks addObject:b];
            [b release];
        }];
        
        // Sort by distance from the camera. Near chunks are first.
        NSArray *sortedChunks = [self sortPointsByDistFromCamera:unsortedChunks]; // is autorelease
        
        // Fill the activeChunks array.
        size_t i = 0;
        for(GSBoxedVector *b in sortedChunks)
        {
            activeChunks[i] = [self getChunkAtPoint:[b v]];
            [activeChunks[i] retain];
            i++;
        }
        assert(i == maxActiveChunks);
        
        [unsortedChunks release];
    } else {
        __block size_t i = 0;
        [self enumeratePointsInActiveRegionUsingBlock: ^(GSVector3 p) {
            activeChunks[i] = [self getChunkAtPoint:p];
            [activeChunks[i] retain];
            i++;
        }];
        assert(i == maxActiveChunks);
    }
    
    // Now release all the chunks in tmpActiveChunks. Chunks which remain in the
    // active region have the same refcount as when we started the update. Chunks
    // which left the active region are released entirely.
    [tmpActiveChunks release];
    
    // Clean up
    [pool release];
}


- (void)recalculateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
    // If the camera moved then recalculate the set of active chunks.
	if(flags & CAMERA_MOVED) {
		// Update camera for each of the skybox faces.
		for(unsigned i = 0; i < 6; ++i)
		{
			[skyboxCamera[i] moveToPosition:[camera cameraEye]];
		}
		
		[self computeActiveChunks:NO];
        
	}
	
	// If the camera moved or turned then recalculate chunk visibility.
	if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        [self computeChunkVisibility];
	}
}


- (void)drawFeelerRays
{
	glDisable(GL_LIGHTING);
	glDisable(GL_TEXTURE_2D);
	glBegin(GL_LINES);
	
	for(GSBoxedRay *r in feelerRays)
    {
		glVertex3f(r.ray.origin.x, r.ray.origin.y, r.ray.origin.z);
		glVertex3f(r.ray.origin.x + r.ray.direction.x,
				   r.ray.origin.y + r.ray.direction.y,
				   r.ray.origin.z + r.ray.direction.z);
    }
	
	glEnd();
	glEnable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
}

@end
