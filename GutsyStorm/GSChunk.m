//
//  GSChunk.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunk.h"
#import "GSNoise.h"

#define CONDITION_VOXEL_DATA_READY (1)
#define CONDITION_GEOMETRY_READY (1)
#define INDEX(x,y,z) ((size_t)(((x)*CHUNK_SIZE_Y*CHUNK_SIZE_Z) + ((y)*CHUNK_SIZE_Z) + (z)))


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat **verts,
                      GLfloat **norms,
                      GLfloat **txcds);
static GLfloat * allocateGeometryBuffer(size_t numVerts);
static float groundGradient(float terrainHeight, GSVector3 p);
static BOOL isGround(float terrainHeight, GSNoise *noiseSource0, GSNoise *noiseSource1, GSVector3 p);


@interface GSChunk (Private)

- (void)generateGeometry;
- (BOOL)tryToGenerateVBOs;
- (void)destroyVoxelData;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (BOOL)getVoxelValueWithX:(size_t)x y:(size_t)y z:(size_t)z;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                _texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                    _normsBuffer:(GLfloat **)_normsBuffer
                                    _vertsBuffer:(GLfloat **)_vertsBuffer;
- (void)generateVoxelDataWithSeed:(unsigned)seed terrainHeight:(float)terrainHeight;
- (void)allocateVoxelData;

@end


@implementation GSChunk

@synthesize minP;
@synthesize maxP;

- (id)initWithSeed:(unsigned)seed minP:(GSVector3)myMinP terrainHeight:(float)terrainHeight
{
    self = [super init];
    if (self) {
        // Initialization code here.        
        assert(terrainHeight >= 0.0 && terrainHeight <= CHUNK_SIZE_Y);
        
        minP = myMinP;
        maxP = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
        numElementsInVBO = 0;
        
        lockVoxelData = [[NSConditionLock alloc] init];
        voxelData = NULL;
        
        lockGeometry = [[NSConditionLock alloc] init];
        numChunkVerts = 0;
        vertsBuffer = NULL;
        normsBuffer = NULL;
        texCoordsBuffer = NULL;
        
        // Frustum-Box testing requires the corners of the cube, so pre-calculate them here.
        corners[0] = minP;
        corners[1] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GSVector3_Add(minP, GSVector3_Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, 0));
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        // Fire off asynchronous task to generate voxel data.
        // When this finishes, the condition in lockVoxelData will be set to CONDITION_VOXEL_DATA_READY.
        dispatch_async(queue, ^{
            [self retain]; // In case chunk is released by the chunk store before operation finishes.
            [self generateVoxelDataWithSeed:seed terrainHeight:terrainHeight];
            [self release];
        });
        
        // Fire off asynchronous task to generate chunk geometry from voxel data. (depends on voxelData)
        // When this finishes, the condition in lockGeometry will be set to CONDITION_GEOMETRY_READY.
        dispatch_async(queue, ^{
            [self retain]; // In case chunk is released by the chunk store before operation finishes.
            [self generateGeometry];
            [self release];
        });
    }
    
    return self;
}


- (void)draw
{
    // If VBOs have not been generated yet then attempt to do so now.
    // OpenGL has no support for concurrency so we can't do this asynchronously.
    // (Unless we use a global lock on OpenGL, but that sounds too complicated to deal with across the entire application.)
    if(!vboChunkVerts || !vboChunkNorms || !vboChunkTexCoords) {
        // If VBOs cannot be generated yet then bail out.
        if(![self tryToGenerateVBOs]) {
            return;
        }
    }
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
    glVertexPointer(3, GL_FLOAT, 0, 0);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
    glNormalPointer(GL_FLOAT, 0, 0);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
    glTexCoordPointer(3, GL_FLOAT, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, numElementsInVBO);
}


- (void)dealloc
{
    [self destroyVBOs];
    
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

@end


@implementation GSChunk (Private)

// Assumes the caller is already holding "lockVoxelData".
- (BOOL)getVoxelValueWithX:(size_t)x y:(size_t)y z:(size_t)z
{
    assert(x < CHUNK_SIZE_X);
    assert(y < CHUNK_SIZE_Y);
    assert(z < CHUNK_SIZE_Z);
    
    return voxelData[INDEX(x, y, z)];
}


// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
    [self destroyVoxelData];
    
    voxelData = malloc(sizeof(BOOL) * CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z);
    if(!voxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for chunk's voxelData"];
    }
    bzero(voxelData, sizeof(BOOL) * CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z);
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
    
    for(size_t x = 0; x < CHUNK_SIZE_X; ++x)
    {
        for(size_t y = 0; y < CHUNK_SIZE_Y; ++y)
        {
            for(size_t z = 0; z < CHUNK_SIZE_Z; ++z)
            {
                GSVector3 p = GSVector3_Add(GSVector3_Make(x, y, z), minP);
                BOOL g = isGround(terrainHeight, noiseSource0, noiseSource1, p);
                voxelData[INDEX(x, y, z)] = g;
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
    
    numChunkVerts = 0;
}


// Assumes the caller is already holding "lockVoxelData" and "lockGeometry".
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                _texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                    _normsBuffer:(GLfloat **)_normsBuffer
                                    _vertsBuffer:(GLfloat **)_vertsBuffer
{
    GLfloat x, y, z, minX, minY, minZ, maxX, maxY, maxZ;
    BOOL onlyDoingCounting = !(_texCoordsBuffer && _normsBuffer && _vertsBuffer);
    
    x = pos.x;
    y = pos.y;
    z = pos.z;
    
    minX = minP.x;
    minY = minP.y;
    minZ = minP.z;

    maxX = maxP.x;
    maxY = maxP.y;
    maxZ = maxP.z;
    
    if(![self getVoxelValueWithX:x-minX y:y-minY z:z-minZ]) {
        return;
    }
    
    const GLfloat L = 0.5f; // half the length of a block along one side
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    GLfloat page = dirt;
                    
    // Top Face
    if(!(y+1<maxY && [self getVoxelValueWithX:x-minX y:y-minY+1 z:z-minZ])) {
        page = side;
        
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x-L, y+L, z+L,
                      0, 1, 0,
                      1, 1, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z-L,
                      0, 1, 0,
                      0, 0, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y+L, z-L,
                      0, 1, 0,
                      1, 0, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x-L, y+L, z+L,
                      0, 1, 0,
                      1, 1, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z+L,
                      0, 1, 0,
                      0, 1, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z-L,
                      0, 1, 0,
                      0, 0, grass,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
    }

    // Bottom Face
    if(!(y-1>=minY && [self getVoxelValueWithX:x-minX y:y-minY-1 z:z-minZ])) {
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x-L, y-L, z-L,
                      0, -1, 0,
                      1, 0, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z-L,
                      0, -1, 0,
                      0, 0, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y-L, z+L,
                      0, -1, 0,
                      1, 1, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x+L, y-L, z-L,
                      0, -1, 0,
                      0, 0, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z+L,
                      0, -1, 0,
                      0, 1, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y-L, z+L,
                      0, -1, 0,
                      1, 1, dirt,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
    }

    // Front Face
    if(!(z+1<maxZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ+1])) {
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x-L, y-L, z+L,
                      0, 0, 1,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z+L,
                      0, 0, 1,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y+L, z+L,
                      0, 0, 1,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x-L, y-L, z+L,
                      0, 0, 1,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z+L,
                      0, 0, 1,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z+L,
                      0, 0, 1,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
    }

    // Back Face
    if(!(z-1>=minZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ-1])) {
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x-L, y+L, z-L,
                      0, 0, -1,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z-L,
                      0, 0, -1,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y-L, z-L,
                      0, 0, -1,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x+L, y+L, z-L,
                      0, 0, -1,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z-L,
                      0, 0, -1,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y-L, z-L,
                      0, 0, -1,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
    }

    // Right Face
    if(!(x+1<maxX && [self getVoxelValueWithX:x-minX+1 y:y-minY z:z-minZ])) {
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x+L, y+L, z-L,
                      1, 0, 0,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z+L,
                      1, 0, 0,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z+L,
                      1, 0, 0,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x+L, y-L, z-L,
                      1, 0, 0,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y+L, z-L,
                      1, 0, 0,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x+L, y-L, z+L,
                      1, 0, 0,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
    }

    // Left Face
    if(!(x-1>=minX && [self getVoxelValueWithX:x-minX-1 y:y-minY z:z-minZ])) {
        if(!onlyDoingCounting) {
            // Face 1
            addVertex(x-L, y-L, z+L,
                      -1, 0, 0,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y+L, z+L,
                      -1, 0, 0,
                      1, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y+L, z-L,
                      -1, 0, 0,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            // Face 2
            addVertex(x-L, y-L, z+L,
                      -1, 0, 0,
                      1, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y+L, z-L,
                      -1, 0, 0,
                      0, 0, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
            
            addVertex(x-L, y-L, z-L,
                      -1, 0, 0,
                      0, 1, page,
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer);
        }
        
        numChunkVerts += 6;
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
    
    // Iterate over all voxels in the chunk and count the number of vertices required.
    numChunkVerts = 0;
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                // Generates no gemeotry, only increments "numChunkVerts" for verts it needs.
                [self generateGeometryForSingleBlockAtPosition:pos
                                              _texCoordsBuffer:NULL
                                                  _normsBuffer:NULL
                                                  _vertsBuffer:NULL];
                
            }
        }
    }
    
    // Allocate memory for geometry.
    vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);

    // Iterate over all voxels in the chunk and generate geometry.
    numChunkVerts = 0;
    GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
                                              _texCoordsBuffer:&_texCoordsBuffer
                                                  _normsBuffer:&_normsBuffer
                                                  _vertsBuffer:&_vertsBuffer];

            }
        }
    }
    
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
    
    numElementsInVBO = 3 * numChunkVerts;
    const GLsizeiptr len = numElementsInVBO * sizeof(GLfloat);
    
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


- (void)destroyVBOs
{
    if(vboChunkVerts) {
        glDeleteBuffers(1, &vboChunkVerts);
        vboChunkVerts = 0;   
    }
    
    if(vboChunkNorms) {
        glDeleteBuffers(1, &vboChunkNorms);
        vboChunkNorms = 0;   
    }
    
    if(vboChunkTexCoords) {
        glDeleteBuffers(1, &vboChunkTexCoords);
        vboChunkTexCoords = 0;   
    }
    
    numElementsInVBO = 0;
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
    const float freqScale = 0.015;
    float n = [noiseSource0 getNoiseAtPoint:GSVector3_Scale(p, freqScale)];
    float turbScaleX = 1.1;
    float turbScaleY = terrainHeight / 2.0;
    float yFreq = turbScaleX * ((n+1) / 2.0);
    float t = turbScaleY * [noiseSource1 getNoiseAtPoint:GSVector3_Make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
    GSVector3 pPrime = GSVector3_Make(p.x, p.y + t, p.z);
    return groundGradient(terrainHeight, pPrime) <= 0;
}


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat **verts,
                      GLfloat **norms,
                      GLfloat **txcds)
{
    **verts = vx; (*verts)++;
    **verts = vy; (*verts)++;
    **verts = vz; (*verts)++;
    
    **norms = nx; (*norms)++;
    **norms = ny; (*norms)++;
    **norms = nz; (*norms)++;
    
    **txcds = tx; (*txcds)++;
    **txcds = ty; (*txcds)++;
    **txcds = tz; (*txcds)++;
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
