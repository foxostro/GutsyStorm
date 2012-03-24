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
static GLfloat * allocateLargestPossibleGeometryBuffer(void);
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

- (id)initWithSeed:(unsigned)seed minP:(GSVector3)myMinP maxP:(GSVector3)myMaxP terrainHeight:(float)terrainHeight
{
    self = [super init];
    if (self) {
        // Initialization code here.
        assert(myMinP.x >= 0);
        assert(myMinP.y >= 0);
        assert(myMinP.z >= 0);
        
        assert(myMaxP.x >= 0);
        assert(myMaxP.y >= 0);
        assert(myMaxP.z >= 0);
        
        assert(myMaxP.x - myMinP.x <= CHUNK_SIZE_X);
        assert(myMaxP.y - myMinP.y <= CHUNK_SIZE_Y);
        assert(myMaxP.z - myMinP.z <= CHUNK_SIZE_Z);
        assert(terrainHeight >= 0.0 && terrainHeight <= CHUNK_SIZE_Y);
        
        minP = myMinP;
        maxP = myMaxP;
        
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
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        // Fire off asynchonous task to generate voxel data.
        dispatch_async(queue, ^{
            [self retain]; // In case chunk is released by the chunk store before operation finishes.
            [self generateVoxelDataWithSeed:seed terrainHeight:terrainHeight];
            [self release];
        });
        
        // Fire off asynchonous task to generate chunk geometry from voxel data.
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
    if(!vboChunkVerts || !vboChunkNorms || !vboChunkTexCoords) {
        // If VBOs cannot be generated yet then bail out.
        if(![self tryToGenerateVBOs]) {
            return;
        }
    }
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
    glVertexPointer(3, GL_FLOAT, 0, 0);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
    glNormalPointer(GL_FLOAT, 0, 0);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
    glTexCoordPointer(3, GL_FLOAT, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, numElementsInVBO);
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
}


- (void)dealloc
{
    [self destroyVoxelData];
    [self destroyGeometry];
    [self destroyVBOs];
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
    const size_t minX = minP.x;
    const size_t minY = minP.y;
    const size_t minZ = minP.z;
    const size_t maxX = maxP.x;
    const size_t maxY = maxP.y;
    const size_t maxZ = maxP.z;
    
    [lockVoxelData lock];
    
    [self allocateVoxelData];
    
    GSNoise *noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
    GSNoise *noiseSource1 = [[GSNoise alloc] initWithSeed:(seed+1)];
    
    for(size_t x = minX; x < maxX; ++x)
    {
        for(size_t y = minY; y < maxY; ++y)
        {
            for(size_t z = minZ; z < maxZ; ++z)
            {
                BOOL g = isGround(terrainHeight, noiseSource0, noiseSource1, GSVector3_Make(x, y, z));
                voxelData[INDEX(x - minX, y - minY, z - minZ)] = g;
            }
        }
    }
    
    [noiseSource0 release];
    [noiseSource1 release];
    
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
        
        // Face 1
        addVertex(x-L, y+L, z+L,
                  0, 1, 0,
                  1, 1, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 1, 0,
                  0, 0, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  0, 1, 0,
                  1, 0, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y+L, z+L,
                  0, 1, 0,
                  1, 1, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 1, 0,
                  0, 1, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 1, 0,
                  0, 0, grass,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Bottom Face
    if(!(y-1>=minY && [self getVoxelValueWithX:x-minX y:y-minY-1 z:z-minZ])) {
        // Face 1
        addVertex(x-L, y-L, z-L,
                  0, -1, 0,
                  1, 0, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z-L,
                  0, -1, 0,
                  0, 0, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z+L,
                  0, -1, 0,
                  1, 1, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y-L, z-L,
                  0, -1, 0,
                  0, 0, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  0, -1, 0,
                  0, 1, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z+L,
                  0, -1, 0,
                  1, 1, dirt,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Front Face
    if(!(z+1<maxZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ+1])) {
        // Face 1
        addVertex(x-L, y-L, z+L,
                  0, 0, 1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 0, 1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z+L,
                  0, 0, 1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y-L, z+L,
                  0, 0, 1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  0, 0, 1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 0, 1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Back Face
    if(!(z-1>=minZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ-1])) {
        // Face 1
        addVertex(x-L, y+L, z-L,
                  0, 0, -1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 0, -1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  0, 0, -1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y+L, z-L,
                  0, 0, -1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z-L,
                  0, 0, -1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  0, 0, -1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Right Face
    if(!(x+1<maxX && [self getVoxelValueWithX:x-minX+1 y:y-minY z:z-minZ])) {
        // Face 1
        addVertex(x+L, y+L, z-L,
                  1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y-L, z-L,
                  1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Left Face
    if(!(x-1>=minX && [self getVoxelValueWithX:x-minX-1 y:y-minY z:z-minZ])) {
        // Face 1
        addVertex(x-L, y-L, z+L,
                  -1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z+L,
                  -1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  -1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y-L, z+L,
                  -1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  -1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  -1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }
}


// Generates verts, norms, and texCoords buffers from voxelData
- (void)generateGeometry
{
    [lockGeometry lock];
    [self destroyGeometry];
    
    // Allocate the largest amount of geometry storage that a chunk might need. We'll end up using a smaller amount by the end.
    GLfloat *tmpVertsBuffer = allocateLargestPossibleGeometryBuffer();
    GLfloat *tmpNormsBuffer = allocateLargestPossibleGeometryBuffer();
    GLfloat *tmpTexCoordsBuffer = allocateLargestPossibleGeometryBuffer();
    
    GLfloat *_vertsBuffer = tmpVertsBuffer;
    GLfloat *_normsBuffer = tmpNormsBuffer;
    GLfloat *_texCoordsBuffer = tmpTexCoordsBuffer;
    
    numChunkVerts = 0;

    // Iterate over all voxels in the chunk.
    GSVector3 pos;
    [lockVoxelData lockWhenCondition:CONDITION_VOXEL_DATA_READY];
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
    
    // Reallocate to buffers for chunk geometry that are sized correctly.
    // These buffers are probably much smaller than the maximum possible.
    size_t len = sizeof(GLfloat) * numChunkVerts * 3;
    
    vertsBuffer = realloc(tmpVertsBuffer, len);
    if(!vertsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating vertsBuffer."];
    }
    
    normsBuffer = realloc(tmpNormsBuffer, len);
    if(!normsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating normsBuffer."];
    }
    
    texCoordsBuffer = realloc(tmpTexCoordsBuffer, len);
    if(!texCoordsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating texCoordsBuffer."];
    }
    
    NSLog(@"Finished generating chunk geometry.");
    [lockGeometry unlockWithCondition:CONDITION_GEOMETRY_READY];
}


- (BOOL)tryToGenerateVBOs
{
    if(![lockGeometry tryLockWhenCondition:CONDITION_GEOMETRY_READY]) {
        return NO;
    }
        
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
    
    NSLog(@"Finished generating chunk VBOs.");
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
    float n = [noiseSource0 getNoiseAtPoint:p];
    float turbScaleX = 1.5;
    float turbScaleY = terrainHeight / 2.0;
    float yFreq = turbScaleX * ((n+1) / 2.0);
    float t = turbScaleY * [noiseSource1 getNoiseAtPoint:GSVector3_Make(p.x, p.y*yFreq, p.z)];
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


// Allocate the largest buffer that could possibly be needed.
static GLfloat * allocateLargestPossibleGeometryBuffer(void)
{
    const size_t maxPossibleVerts = 36 * CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z;
    
    GLfloat *buffer = malloc(sizeof(GLfloat) * maxPossibleVerts * 3);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    bzero(buffer, sizeof(GLfloat) * maxPossibleVerts * 3);
    
    return buffer;
}
