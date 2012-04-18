//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkGeometryData.h"
#import "GSChunkVoxelData.h"
#import "GSVertex.h"

#define CONDITION_GEOMETRY_READY (1)


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      NSMutableArray *vertices,
                      NSMutableArray *indices);

static GLfloat * allocateGeometryBuffer(size_t numVerts);


@interface GSChunkGeometryData (Private)

- (void)generateGeometryWithVoxelData:(GSChunkVoxelData *)voxels;
- (BOOL)tryToGenerateVBOs;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
										vertices:(NSMutableArray *)vertices
										 indices:(NSMutableArray *)indices
									   voxelData:(GSChunkVoxelData *)voxels;

@end


@implementation GSChunkGeometryData


- (id)initWithMinP:(GSVector3)_minP
		voxelData:(GSChunkVoxelData *)voxels
{
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
        
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
        
        // Fire off asynchronous task to generate chunk geometry from voxel data. (depends on voxelData)
        // When this finishes, the condition in lockGeometry will be set to CONDITION_GEOMETRY_READY.
        dispatch_async(queue, ^{
            [self generateGeometryWithVoxelData:voxels];
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


- (void)dealloc
{
	// VBOs must be destroyed on the main thread as all OpenGL calls must be done on the main thread.
	[self performSelectorOnMainThread:@selector(destroyVBOs) withObject:self waitUntilDone:YES];
	
    [lockGeometry lock];
    [self destroyGeometry];
    [lockGeometry unlock];
    [lockGeometry release];
    
	[super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)


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
									   voxelData:(GSChunkVoxelData *)voxels;
{
    GLfloat x, y, z, minX, minY, minZ;
    
    x = pos.x;
    y = pos.y;
    z = pos.z;
    
    minX = minP.x;
    minY = minP.y;
    minZ = minP.z;
    
    if([voxels getVoxelValueWithX:x-minX y:y-minY z:z-minZ].empty) {
        return;
    }
    
    const GLfloat L = 0.5f; // half the length of a block along one side
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    GLfloat page = dirt;
	
    // Top Face
    if([voxels getVoxelValueWithX:x-minX y:y-minY+1 z:z-minZ].empty) {
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
    if([voxels getVoxelValueWithX:x-minX y:y-minY-1 z:z-minZ].empty) {
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
    if([voxels getVoxelValueWithX:x-minX y:y-minY z:z-minZ+1].empty) {
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
    if([voxels getVoxelValueWithX:x-minX y:y-minY z:z-minZ-1].empty) {
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
	if([voxels getVoxelValueWithX:x-minX+1 y:y-minY z:z-minZ].empty) {
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
    if([voxels getVoxelValueWithX:x-minX-1 y:y-minY z:z-minZ].empty) {
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
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData *)voxels
{
    GSVector3 pos;
	
	[lockGeometry lock];
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
	
    [self destroyGeometry];
    
    // Iterate over all voxels in the chunk and generate geometry.
	NSMutableArray *vertices = [[NSMutableArray alloc] init];
	NSMutableArray *indices = [[NSMutableArray alloc] init];
    [voxels.lockVoxelData lockWhenCondition:CONDITION_VOXEL_DATA_READY];
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
													  vertices:vertices
													   indices:indices
													 voxelData:voxels];
				
            }
        }
    }
	[voxels.lockVoxelData unlock];
    
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
	
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk geometry. It took %.3fs, including time to wait for voxels.", timeEnd - timeStart);
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