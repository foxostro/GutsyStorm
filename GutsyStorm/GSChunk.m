//
//  GSChunk.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunk.h"
#import "GSNoise.h"
#import "GSVertex.h"

#define CONDITION_VOXEL_DATA_READY (1)
#define CONDITION_GEOMETRY_READY (1)
#define INDEX(x,y,z) ((size_t)(((x+1)*(CHUNK_SIZE_Y+2)*(CHUNK_SIZE_Z+2)) + ((y+1)*(CHUNK_SIZE_Z+2)) + (z+1)))


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      NSMutableArray *vertices,
                      NSMutableArray *indices);
static GLfloat * allocateGeometryBuffer(size_t numVerts);
static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunk (Private)

- (void)generateGeometry;
- (BOOL)tryToGenerateVBOs;
- (void)destroyVoxelData;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
										vertices:(NSMutableArray *)vertices
										 indices:(NSMutableArray *)indices;
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight;
- (void)allocateVoxelData;

- (BOOL)getVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z;
- (void)setVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z value:(BOOL)value;

@end


@implementation GSChunk

@synthesize minP;
@synthesize maxP;


+ (NSString *)computeChunkFileNameWithMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.chunk", minP.x, minP.y, minP.z];
}


- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)myMinP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder
{
    self = [super init];
    if (self) {
        // Initialization code here.        
        assert(terrainHeight >= 0.0);
        
        minP = myMinP;
        maxP = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
        
        lockVoxelData = [[NSConditionLock alloc] init];
        voxelData = NULL;
        
        lockGeometry = [[NSConditionLock alloc] init];
        vertsBuffer = NULL;
        normsBuffer = NULL;
        texCoordsBuffer = NULL;
        indexBuffer = NULL;
        numChunkVerts = 0;
        numIndices = 0;
		
        // Frustum-Box testing requires the corners of the cube, so pre-calculate them here.
        corners[0] = minP;
        corners[1] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GSVector3_Add(minP, GSVector3_Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, 0));
		
		visible = NO;
        
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		// Fire off asynchronous task to generate voxel data.
        // When this finishes, the condition in lockVoxelData will be set to CONDITION_VOXEL_DATA_READY.
        dispatch_async(queue, ^{
			NSURL *url = [NSURL URLWithString:[GSChunk computeChunkFileNameWithMinP:minP]
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
        
        // Fire off asynchronous task to generate chunk geometry from voxel data. (depends on voxelData)
        // When this finishes, the condition in lockGeometry will be set to CONDITION_GEOMETRY_READY.
        dispatch_async(queue, ^{
            [self generateGeometry];
        });
    }
    
    return self;
}


// Returns YES if VBOs were generated.
- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration
{
	BOOL didGenerateVBOs = NO;
	
	if(numIndices <= 0) {
		return didGenerateVBOs;
	}
	
    // If VBOs have not been generated yet then attempt to do so now.
    // OpenGL has no support for concurrency so we can't do this asynchronously.
    // (Unless we use a global lock on OpenGL, but that sounds too complicated to deal with across the entire application.)
    if(!vboChunkVerts || !vboChunkNorms || !vboChunkTexCoords) {
        // If VBOs cannot be generated yet then bail out.
        if(allowVBOGeneration && ![self tryToGenerateVBOs]) {
            return NO;
        } else {
			didGenerateVBOs = YES;
		}
    }
    
	if(vboChunkVerts && vboChunkNorms && vboChunkTexCoords) {
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
		glVertexPointer(3, GL_FLOAT, 0, 0);
		
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
		glNormalPointer(GL_FLOAT, 0, 0);
		
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
		glTexCoordPointer(3, GL_FLOAT, 0, 0);
		
		glDrawElements(GL_QUADS, numIndices, GL_UNSIGNED_SHORT, indexBuffer);
	}
	
	return didGenerateVBOs;
}


- (void)saveToFileWithContainingFolder:(NSURL *)folder
{
	const size_t len = (CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2) * sizeof(BOOL);
	
	NSURL *url = [NSURL URLWithString:[GSChunk computeChunkFileNameWithMinP:minP]
						relativeToURL:folder];
	
	[lockVoxelData lockWhenCondition:CONDITION_VOXEL_DATA_READY];
	[[NSData dataWithBytes:voxelData length:len] writeToURL:url atomically:YES];
	[lockVoxelData unlock];
}


// Returns YES if the chunk data is reachable on the filesystem and loading was successful.
- (void)loadFromFile:(NSURL *)url
{
	const size_t len = (CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2) * sizeof(BOOL);
	
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
	
	[lockVoxelData unlockWithCondition:CONDITION_VOXEL_DATA_READY];
}


- (void)dealloc
{
	// VBOs must be destroyed on the main thread as all OpenGL calls must be done on the main thread.
	[self performSelectorOnMainThread:@selector(destroyVBOs) withObject:self waitUntilDone:YES];
	
    // Grab locks in case we are deallocated while an operation is in flight.
    // XXX: So, this would block the main thread for an indeterminate amount of time in that case?
    [lockVoxelData lock];
    [lockGeometry lock];
    [self destroyVoxelData];
    [self destroyGeometry];
    [lockGeometry unlock];
    [lockVoxelData unlock];
    
    [lockVoxelData release];
    [lockGeometry release];
    
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

@end


@implementation GSChunk (Private)

// Assumes the caller is already holding "lockVoxelData".
- (BOOL)getVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z
{
    assert(x >= -1 && x < CHUNK_SIZE_X+1);
    assert(y >= -1 && y < CHUNK_SIZE_Y+1);
    assert(z >= -1 && z < CHUNK_SIZE_Z+1);
	
	size_t idx = INDEX(x, y, z);
	assert(idx >= 0 && idx < ((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2)));
    
    return voxelData[idx];
}


// Assumes the caller is already holding "lockVoxelData".
- (void)setVoxelValueWithX:(ssize_t)x y:(ssize_t)y z:(ssize_t)z value:(BOOL)value
{
    assert(x >= -1 && x < CHUNK_SIZE_X+1);
    assert(y >= -1 && y < CHUNK_SIZE_Y+1);
    assert(z >= -1 && z < CHUNK_SIZE_Z+1);
	
	size_t idx = INDEX(x, y, z);
	assert(idx >= 0 && idx < ((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2)));
    
    voxelData[idx] = value;
}


// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
	[self destroyVoxelData];
    
    voxelData = calloc((CHUNK_SIZE_X+2) * (CHUNK_SIZE_Y+2) * (CHUNK_SIZE_Z+2), sizeof(BOOL));
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


/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
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
                BOOL g = isGround(terrainHeight, noiseSource0, noiseSource1, p);
				[self setVoxelValueWithX:x y:y z:z value:g];
            }
        }
    }
    
    [noiseSource0 release];
    [noiseSource1 release];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk voxel data. It took %.3fs", timeEnd - timeStart);
    [lockVoxelData unlockWithCondition:CONDITION_VOXEL_DATA_READY];
}


// Assumes the caller is already holding "lockGeometry".
- (void)destroyGeometry
{
    free(vertsBuffer);
    vertsBuffer = NULL;
    
    free(normsBuffer);
    normsBuffer = NULL;
    
    free(texCoordsBuffer);
    texCoordsBuffer = NULL;
	
	free(indexBuffer);
	indexBuffer = NULL;
    
	numChunkVerts = 0;
    numIndices = 0;
}


// Assumes the caller is already holding "lockVoxelData" and "lockGeometry".
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
										vertices:(NSMutableArray *)vertices
										 indices:(NSMutableArray *)indices
{
    GLfloat x, y, z, minX, minY, minZ;
    
    x = pos.x;
    y = pos.y;
    z = pos.z;
    
    minX = minP.x;
    minY = minP.y;
    minZ = minP.z;
    
    if(![self getVoxelValueWithX:x-minX y:y-minY z:z-minZ]) {
        return;
    }
    
    const GLfloat L = 0.5f; // half the length of a block along one side
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    GLfloat page = dirt;
                    
    // Top Face
    if(![self getVoxelValueWithX:x-minX y:y-minY+1 z:z-minZ]) {
        page = side;
		
		addVertex(x-L, y+L, z-L,
				  0, 1, 0,
				  1, 0, grass,
				  vertices,
				  indices);
        
		addVertex(x-L, y+L, z+L,
				  0, 1, 0,
				  1, 1, grass,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  0, 1, 0,
				  0, 1, grass,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  0, 1, 0,
				  0, 0, grass,
				  vertices,
				  indices);
    }

    // Bottom Face
    if(![self getVoxelValueWithX:x-minX y:y-minY-1 z:z-minZ]) {
		addVertex(x-L, y-L, z-L,
				  0, -1, 0,
				  1, 0, dirt,
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z-L,
				  0, -1, 0,
				  0, 0, dirt,
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  0, -1, 0,
				  0, 1, dirt,
				  vertices,
				  indices);
		
		addVertex(x-L, y-L, z+L,
				  0, -1, 0,
				  1, 1, dirt,
				  vertices,
				  indices);
    }

    // Front Face
    if(![self getVoxelValueWithX:x-minX y:y-minY z:z-minZ+1]) {
		addVertex(x-L, y-L, z+L,
				  0, 0, 1,
				  0, 1, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  0, 0, 1,
				  1, 1, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  0, 0, 1,
				  1, 0, page,
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z+L,
				  0, 0, 1,
				  0, 0, page,
				  vertices,
				  indices);
    }

    // Back Face
    if(![self getVoxelValueWithX:x-minX y:y-minY z:z-minZ-1]) {
		addVertex(x-L, y-L, z-L,
				  0, 1, -1,
				  0, 1, page,
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z-L,
				  0, 1, -1,
				  0, 0, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  0, 1, -1,
				  1, 0, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z-L,
				  0, 1, -1,
				  1, 1, page,
				  vertices,
				  indices);
    }

    // Right Face
	if(![self getVoxelValueWithX:x-minX+1 y:y-minY z:z-minZ]) {
		addVertex(x+L, y-L, z-L,
				  1, 0, 0,
				  0, 1, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  1, 0, 0,
				  0, 0, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  1, 0, 0,
				  1, 0, page,
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  1, 0, 0,
				  1, 1, page,
				  vertices,
				  indices);
    }

    // Left Face
    if(![self getVoxelValueWithX:x-minX-1 y:y-minY z:z-minZ]) {
		addVertex(x-L, y-L, z-L,
				  -1, 0, 0,
				  0, 1, page,
				  vertices,
				  indices);
		
		addVertex(x-L, y-L, z+L,
				  -1, 0, 0,
				  1, 1, page,
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z+L,
				  -1, 0, 0,
				  1, 0, page,
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z-L,
				  -1, 0, 0,
				  0, 0, page,
				  vertices,
				  indices);
    }
}


// Generates verts, norms, and texCoords buffers from voxelData
- (void)generateGeometry
{
    GSVector3 pos;
    
    [lockGeometry lock];
    [self destroyGeometry];
    
    [lockVoxelData lockWhenCondition:CONDITION_VOXEL_DATA_READY];
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    
    // Iterate over all voxels in the chunk and generate geometry.
	NSMutableArray *vertices = [[NSMutableArray alloc] init];
	NSMutableArray *indices = [[NSMutableArray alloc] init];
	
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
													  vertices:vertices
													   indices:indices];

            }
        }
    }
    
    numChunkVerts = (GLsizei)[vertices count];
    numIndices = (GLsizei)[indices count];
    
	// Take the vertices array and generate raw buffers for OpenGL to consume.
	assert(numChunkVerts < 65536);
	vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);
	
	GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
	for(GSVertex *vertex in vertices)
	{
		_vertsBuffer[0] = vertex.position.v.x;
		_vertsBuffer[1] = vertex.position.v.y;
		_vertsBuffer[2] = vertex.position.v.z;
		_vertsBuffer += 3;
		
		_normsBuffer[0] = vertex.normal.v.x;
		_normsBuffer[1] = vertex.normal.v.y;
		_normsBuffer[2] = vertex.normal.v.z;
		_normsBuffer += 3;
		
		_texCoordsBuffer[0] = vertex.texCoord.v.x;
		_texCoordsBuffer[1] = vertex.texCoord.v.y;
		_texCoordsBuffer[2] = vertex.texCoord.v.z;
		_texCoordsBuffer += 3;
	}
	
	[vertices release];
	
	// Take the indices array and generate a raw index buffer for OpenGL to consume.
	indexBuffer = malloc(sizeof(GLushort) * numIndices);
    if(!indexBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
    }
	
	for(GLsizei i = 0; i < numIndices; ++i)
	{
		indexBuffer[i] = [[indices objectAtIndex:i] unsignedIntValue];
	}
	
	[indices release];
    
    [lockVoxelData unlock];
	
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk geometry. It took %.3fs after voxel data was ready.", timeEnd - timeStart);
    [lockGeometry unlockWithCondition:CONDITION_GEOMETRY_READY];
}


- (BOOL)tryToGenerateVBOs
{
    if(![lockGeometry tryLockWhenCondition:CONDITION_GEOMETRY_READY]) {
        return NO;
    }
    
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    [self destroyVBOs];
    
    const GLsizeiptr len = 3 * numChunkVerts * sizeof(GLfloat);
    
    glGenBuffers(1, &vboChunkVerts);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
    glBufferData(GL_ARRAY_BUFFER, len, vertsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkNorms);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
    glBufferData(GL_ARRAY_BUFFER, len, normsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkTexCoords);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
    glBufferData(GL_ARRAY_BUFFER, len, texCoordsBuffer, GL_STATIC_DRAW);
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk VBOs. It took %.3fs.", timeEnd - timeStart);
    [lockGeometry unlock];
    
    return YES;
}


// Must only be called from the main thread.
- (void)destroyVBOs
{	
    if(vboChunkVerts && glIsBuffer(vboChunkVerts)) {
        glDeleteBuffers(1, &vboChunkVerts);
    }
    
    if(vboChunkNorms && glIsBuffer(vboChunkNorms)) {
        glDeleteBuffers(1, &vboChunkNorms);
    }
    
    if(vboChunkTexCoords && glIsBuffer(vboChunkTexCoords)) {
        glDeleteBuffers(1, &vboChunkTexCoords);
    }
    
	vboChunkVerts = 0;
	vboChunkNorms = 0;
	vboChunkTexCoords = 0;
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


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      NSMutableArray *vertices,
                      NSMutableArray *indices)
{
	GSBoxedVector *position = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(vx, vy, vz)] autorelease];
	GSBoxedVector *normal   = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(nx, ny, nz)] autorelease];
	GSBoxedVector *texCoord = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(tx, ty, tz)] autorelease];
	
	GSVertex *vertex = [[[GSVertex alloc] initWithPosition:position
													normal:normal
												  texCoord:texCoord] autorelease];
	
	[vertices addObject:vertex];
	[indices addObject:[NSNumber numberWithUnsignedInteger:[vertices count]-1]];
}


// Allocate a buffer for use in geometry generation.
static GLfloat * allocateGeometryBuffer(size_t numVerts)
{
    GLfloat *buffer = malloc(sizeof(GLfloat) * 3* numVerts);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    
    return buffer;
}
