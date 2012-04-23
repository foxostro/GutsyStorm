//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkGeometryData.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSVertex.h"


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat  color,
                      NSMutableArray *vertices,
                      NSMutableArray *indices);

static GLfloat * allocateGeometryBuffer(size_t numVerts);


static inline float blockLight(float sunlight, float torchLight, float ambientOcclusion)
{
	return sunlight*ambientOcclusion + torchLight;
}


@interface GSChunkGeometryData (Private)

- (BOOL)tryToGenerateVBOs;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)voxels;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
										vertices:(NSMutableArray *)vertices
										 indices:(NSMutableArray *)indices
									   voxelData:(GSChunkVoxelData **)voxels;

@end


@implementation GSChunkGeometryData


- (id)initWithMinP:(GSVector3)_minP
		 voxelData:(GSChunkVoxelData **)_chunks
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
	
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
		vboChunkColors = 0;
        
        lockGeometry = [[NSConditionLock alloc] init];
		[lockGeometry setName:@"GSChunkGeometryData.lockGeometry"];
		
        vertsBuffer = NULL;
        normsBuffer = NULL;
        texCoordsBuffer = NULL;
		colorBuffer = NULL;
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
		
		dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		dispatch_async(queue, ^{
			[self generateGeometryWithVoxelData:chunks];
			
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
    if(!vboChunkVerts || !vboChunkNorms || !vboChunkTexCoords || !vboChunkColors) {
        // If VBOs cannot be generated yet then bail out.
        if(allowVBOGeneration && ![self tryToGenerateVBOs]) {
            return NO;
        } else {
			didGenerateVBOs = YES;
		}
    }
    
	if(vboChunkVerts && vboChunkNorms && vboChunkTexCoords && vboChunkColors && (numIndices>0) && indexBuffer) {
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
		glVertexPointer(3, GL_FLOAT, 0, 0);
		
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
		glNormalPointer(GL_FLOAT, 0, 0);
		
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
		glTexCoordPointer(3, GL_FLOAT, 0, 0);
		
		glBindBuffer(GL_ARRAY_BUFFER, vboChunkColors);
		glColorPointer(3, GL_FLOAT, 0, 0);
		
		glDrawElements(GL_QUADS, numIndices, GL_UNSIGNED_SHORT, indexBuffer);
	}
	
	return didGenerateVBOs;
}


- (void)dealloc
{
	// VBOs must be destroyed on the main thread as all OpenGL calls must be done on the main thread.
	[self performSelectorOnMainThread:@selector(destroyVBOs) withObject:self waitUntilDone:YES];
	
    [lockGeometry lock];
    [self destroyGeometry];
    [lockGeometry unlockWithCondition:!READY];
    [lockGeometry release];
    
	[super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)

// Generates verts, norms, and texCoords buffers from voxel data.
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)chunks
{
	assert(chunks);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_CENTER]);
	
	GSVector3 pos;
	
	[lockGeometry lock];
	
    [self destroyGeometry];
    
    NSMutableArray *vertices = [[NSMutableArray alloc] init];
	NSMutableArray *indices = [[NSMutableArray alloc] init];
	
    [chunks[CHUNK_NEIGHBOR_CENTER]->lockSunlight lockWhenCondition:READY];
	[chunks[CHUNK_NEIGHBOR_CENTER]->lockAmbientOcclusion lockWhenCondition:READY];
	
	// Atomically, grab all the voxel data we need to generate geometry for this chunk.
	// We do this atomically to prevent deadlock.
	[[GSChunkStore lockWhileLockingMultipleChunks] lock];
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData lockWhenCondition:READY];
	}
	[[GSChunkStore lockWhileLockingMultipleChunks] unlock];
	
	//CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
	
    // Iterate over all voxels in the chunk and generate geometry.
	for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
													  vertices:vertices
													   indices:indices
													 voxelData:chunks];
				
            }
        }
    }
	
	// Give up locks on the neighboring chunks' voxel data.
	for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
	{
		[chunks[i]->lockVoxelData unlockWithCondition:READY];
	}
	
	[chunks[CHUNK_NEIGHBOR_CENTER]->lockAmbientOcclusion unlockWithCondition:READY];
	[chunks[CHUNK_NEIGHBOR_CENTER]->lockSunlight unlockWithCondition:READY];
    
    numChunkVerts = (GLsizei)[vertices count];
    numIndices = (GLsizei)[indices count];
    
	// Take the vertices array and generate raw buffers for OpenGL to consume.
	assert(numChunkVerts < 65536);
	vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);
    colorBuffer = allocateGeometryBuffer(numChunkVerts);
	
	GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
    GLfloat *_colorBuffer = colorBuffer;
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
		
		_colorBuffer[0] = vertex.color.v.x;
		_colorBuffer[1] = vertex.color.v.y;
		_colorBuffer[2] = vertex.color.v.z;
		_colorBuffer += 3;
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
	
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk geometry. It took %.3fs, including time to wait for voxels.", timeEnd - timeStart);
	[lockGeometry unlockWithCondition:READY];
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
    
    free(colorBuffer);
    colorBuffer = NULL;
	
	free(indexBuffer);
	indexBuffer = NULL;
    
	numChunkVerts = 0;
    numIndices = 0;
}


/* Assumes the caller is already holding "lockGeometry", "lockSunlight", "lockAmbientOcclusion",
 * and locks on all neighboring chunks.
 */
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
										vertices:(NSMutableArray *)vertices
										 indices:(NSMutableArray *)indices
									   voxelData:(GSChunkVoxelData **)chunks
{
	assert(vertices);
	assert(indices);
	assert(chunks);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
	assert(chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
	assert(chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
	assert(chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
	assert(chunks[CHUNK_NEIGHBOR_CENTER]);
	
	const GLfloat L = 0.5f; // half the length of a block along one side
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    GLfloat page = dirt;
	
    GLfloat x = pos.x;
    GLfloat y = pos.y;
    GLfloat z = pos.z;
    
    GLfloat minX = minP.x;
    GLfloat minY = minP.y;
	GLfloat minZ = minP.z;
	
	GSIntegerVector3 chunkLocalPos = {x-minX, y-minY, z-minZ};
	
	GSChunkVoxelData *voxels = chunks[CHUNK_NEIGHBOR_CENTER];
	
	voxel_t *thisVoxel = [voxels getPointerToVoxelAtPoint:chunkLocalPos];
    
    if(thisVoxel->empty) {
        return;
    }
    
	int sunlightLightLevel = [chunks[CHUNK_NEIGHBOR_CENTER] getSunlightAtPoint:chunkLocalPos];
    float sunlight = (MAX(0, sunlightLightLevel) / (float)CHUNK_LIGHTING_MAX) * 0.8 + 0.2;
	float torchLight = 0.0; // TODO: add torch lighting to the world.
	ambient_occlusion_t ambientOcclusion = [chunks[CHUNK_NEIGHBOR_CENTER] getAmbientOcclusionAtPoint:chunkLocalPos];
	
    // Top Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY+1, z-minZ), chunks)) {
        page = side;
		
		addVertex(x-L, y+L, z-L,
				  0, 1, 0,
				  1, 0, grass,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftl),
				  vertices,
				  indices);
        
		addVertex(x-L, y+L, z+L,
				  0, 1, 0,
				  1, 1, grass,
				  blockLight(sunlight, torchLight, ambientOcclusion.btl),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  0, 1, 0,
				  0, 1, grass,
				  blockLight(sunlight, torchLight, ambientOcclusion.btr),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  0, 1, 0,
				  0, 0, grass,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftr),
				  vertices,
				  indices);
    }
	
    // Bottom Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY-1, z-minZ), chunks)) {
		addVertex(x-L, y-L, z-L,
				  0, -1, 0,
				  1, 0, dirt,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbl),
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z-L,
				  0, -1, 0,
				  0, 0, dirt,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbr),
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  0, -1, 0,
				  0, 1, dirt,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbr),
				  vertices,
				  indices);
		
		addVertex(x-L, y-L, z+L,
				  0, -1, 0,
				  1, 1, dirt,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbl),
				  vertices,
				  indices);
    }
	
    // Back Face (+Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ+1), chunks)) {
		addVertex(x-L, y-L, z+L,
				  0, 0, 1,
				  0, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbl),
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  0, 0, 1,
				  1, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbr),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  0, 0, 1,
				  1, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.btr),
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z+L,
				  0, 0, 1,
				  0, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.btl),
				  vertices,
				  indices);
    }
	
    // Front Face (-Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ-1), chunks)) {
		addVertex(x-L, y-L, z-L,
				  0, 1, -1,
				  0, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbl),
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z-L,
				  0, 1, -1,
				  0, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftl),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  0, 1, -1,
				  1, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftr),
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z-L,
				  0, 1, -1,
				  1, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbr),
				  vertices,
				  indices);
    }
	
    // Right Face
	if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX+1, y-minY, z-minZ), chunks)) {
		addVertex(x+L, y-L, z-L,
				  1, 0, 0,
				  0, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbr),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z-L,
				  1, 0, 0,
				  0, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftr),
				  vertices,
				  indices);
		
		addVertex(x+L, y+L, z+L,
				  1, 0, 0,
				  1, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.btr),
				  vertices,
				  indices);
		
		addVertex(x+L, y-L, z+L,
				  1, 0, 0,
				  1, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbr),
				  vertices,
				  indices);
    }
	
    // Left Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX-1, y-minY, z-minZ), chunks)) {
		addVertex(x-L, y-L, z-L,
				  -1, 0, 0,
				  0, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.fbl),
				  vertices,
				  indices);
		
		addVertex(x-L, y-L, z+L,
				  -1, 0, 0,
				  1, 1, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.bbl),
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z+L,
				  -1, 0, 0,
				  1, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.btl),
				  vertices,
				  indices);
		
		addVertex(x-L, y+L, z-L,
				  -1, 0, 0,
				  0, 0, page,
				  blockLight(sunlight, torchLight, ambientOcclusion.ftl),
				  vertices,
				  indices);
    }
}


- (BOOL)tryToGenerateVBOs
{
    if(![lockGeometry tryLockWhenCondition:READY]) {
        return NO;
    }
    
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    [self destroyVBOs];
	
	GLsizei len = 3 * numChunkVerts * sizeof(GLfloat);
    
    glGenBuffers(1, &vboChunkVerts);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
    glBufferData(GL_ARRAY_BUFFER, len, vertsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkNorms);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
    glBufferData(GL_ARRAY_BUFFER, len, normsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkTexCoords);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
    glBufferData(GL_ARRAY_BUFFER, len, texCoordsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkColors);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkColors);
    glBufferData(GL_ARRAY_BUFFER, len, colorBuffer, GL_STATIC_DRAW);
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk VBOs. It took %.3fs.", timeEnd - timeStart);
    [lockGeometry unlockWithCondition:READY];
    
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
    
    if(vboChunkColors && glIsBuffer(vboChunkColors)) {
        glDeleteBuffers(1, &vboChunkColors);
    }
    
	vboChunkVerts = 0;
	vboChunkNorms = 0;
	vboChunkTexCoords = 0;
	vboChunkColors = 0;
}

@end


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat  c,
                      NSMutableArray *vertices,
                      NSMutableArray *indices)
{
	GSBoxedVector *position = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(vx, vy, vz)] autorelease];
	GSBoxedVector *normal   = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(nx, ny, nz)] autorelease];
	GSBoxedVector *texCoord = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(tx, ty, tz)] autorelease];
	GSBoxedVector *color = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(c, c, c)] autorelease];
	
	GSVertex *vertex = [[[GSVertex alloc] initWithPosition:position
													normal:normal
												  texCoord:texCoord
													 color:color] autorelease];
	
	[vertices addObject:vertex];
	[indices addObject:[NSNumber numberWithUnsignedInteger:[vertices count]-1]];
}


// Allocate a buffer for use in geometry generation.
static GLfloat * allocateGeometryBuffer(size_t numVerts)
{
    GLfloat *buffer = malloc(sizeof(GLfloat) * 3 * numVerts);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    
    return buffer;
}
