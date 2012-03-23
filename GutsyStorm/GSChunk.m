//
//  GSChunk.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunk.h"

const size_t chunkSizeX = 64;
const size_t chunkSizeY = 64;
const size_t chunkSizeZ = 64;


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat **_vertsBuffer,
                      GLfloat **_normsBuffer,
                      GLfloat **_texCoordsBuffer);

static GLfloat * allocateLargestPossibleGeometryBuffer(void);


@implementation GSChunk

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
        numChunkVerts = 0;
        vertsBuffer = NULL;
        normsBuffer = NULL;
        texCoordsBuffer = NULL;
        
        [self generateVoxelData];
        [self generateGeometry];
        [self generateVBOs];
    }
    
    return self;
}


- (BOOL)getVoxelValueWithX:(size_t)x y:(size_t)y z:(size_t)z
{
    assert(x < chunkSizeX);
    assert(y < chunkSizeY);
    assert(z < chunkSizeZ);    
    return voxelData[(x*chunkSizeY*chunkSizeZ) + (y*chunkSizeY) + z];
}


- (void)generateVoxelData
{
    [self destroyVoxelData];
    
    voxelData = malloc(sizeof(BOOL) * chunkSizeX * chunkSizeY * chunkSizeZ);
    if(!voxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for chunk's voxelData"];
    }
    bzero(voxelData, sizeof(BOOL) * chunkSizeX * chunkSizeY * chunkSizeZ);
    
    for(size_t i = 0; i < (chunkSizeX * chunkSizeY * chunkSizeZ); ++i)
    {
        voxelData[i] = (rand()%2 == 0);
    }
}


- (void)generateGeometryForSingleBlockWithX:(GLfloat)x
                                          y:(GLfloat)y
                                          z:(GLfloat)z
                                       minX:(GLfloat)minX
                                       minY:(GLfloat)minY
                                       minZ:(GLfloat)minZ
                                       maxX:(GLfloat)maxX
                                       maxY:(GLfloat)maxY
                                       maxZ:(GLfloat)maxZ
                         _texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                             _normsBuffer:(GLfloat **)_normsBuffer
                             _vertsBuffer:(GLfloat **)_vertsBuffer
{
    if(![self getVoxelValueWithX:x-minX y:y-minY z:z-minZ]) {
        return;
    }
    
    const GLfloat L = 0.5f;
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
                    
    // Top Face
    if(!(y+1<maxY && [self getVoxelValueWithX:x-minX y:y-minY+1 z:z-minZ])) {
        // This face is exposed to air on the top so use page 1 for the other sides of the block.
        GLfloat page = grass;
        
        // Face 1
        addVertex(x-L, y+L, z+L,
                  0, 1, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 1, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  0, 1, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y+L, z+L,
                  0, 1, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 1, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 1, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Bottom Face
    if(!(y-1>=minY && [self getVoxelValueWithX:x-minX y:y-minY-1 z:z-minZ])) {
        // This face is always dirt.
        GLfloat page = dirt;
        
        // Face 1
        addVertex(x-L, y-L, z-L,
                  0, -1, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z-L,
                  0, -1, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z+L,
                  0, -1, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y-L, z-L,
                  0, -1, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  0, -1, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z+L,
                  0, -1, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Front Face
    if(!(z+1<maxZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ+1])) {
        GLfloat page = side;
        
        // Face 1
        addVertex(x-L, y-L, z+L,
                  0, 0, 1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 0, 1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z+L,
                  0, 0, 1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y-L, z+L,
                  0, 0, 1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  0, 0, 1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  0, 0, 1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Back Face
    if(!(z-1>=minZ && [self getVoxelValueWithX:x-minX y:y-minY z:z-minZ-1])) {
        GLfloat page = side;
        
        // Face 1
        addVertex(x-L, y+L, z-L,
                  0, 0, -1,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  0, 0, -1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  0, 0, -1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y+L, z-L,
                  0, 0, -1,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z-L,
                  0, 0, -1,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  0, 0, -1,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Right Face
    if(!(x+1<maxX && [self getVoxelValueWithX:x-minX+1 y:y-minY z:z-minZ])) {
        GLfloat page = side;
        
        // Face 1
        addVertex(x+L, y+L, z-L,
                  1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z+L,
                  1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x+L, y-L, z-L,
                  1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y+L, z-L,
                  1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x+L, y-L, z+L,
                  1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }

    // Left Face
    if(!(x-1>=minX && [self getVoxelValueWithX:x-minX-1 y:y-minY z:z-minZ])) {
        GLfloat page = side;
        
        // Face 1
        addVertex(x-L, y-L, z+L,
                  -1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z+L,
                  -1, 0, 0,
                  1, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  -1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        // Face 2
        addVertex(x-L, y-L, z+L,
                  -1, 0, 0,
                  1, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y+L, z-L,
                  -1, 0, 0,
                  0, 1, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
        
        addVertex(x-L, y-L, z-L,
                  -1, 0, 0,
                  0, 0, page,
                  _vertsBuffer,
                  _normsBuffer,
                  _texCoordsBuffer);
        numChunkVerts++;
    }
}


// Generates verts, norms, and texCoords buffers from voxelData
- (void)generateGeometry
{
    [self destroyGeometry];
    
    const GLfloat minX = 0;
    const GLfloat minY = 0;
    const GLfloat minZ = 0;
    
    const GLfloat maxX = chunkSizeX;
    const GLfloat maxY = chunkSizeY;
    const GLfloat maxZ = chunkSizeZ;
    
    // Allocate the largest amount of geometry storage that a chunk might need. We'll end up using a smaller amount by the end.
    GLfloat *tmpVertsBuffer = allocateLargestPossibleGeometryBuffer();
    GLfloat *tmpNormsBuffer = allocateLargestPossibleGeometryBuffer();
    GLfloat *tmpTexCoordsBuffer = allocateLargestPossibleGeometryBuffer();
    
    GLfloat *_vertsBuffer = tmpVertsBuffer;
    GLfloat *_normsBuffer = tmpNormsBuffer;
    GLfloat *_texCoordsBuffer = tmpTexCoordsBuffer;
    
    numChunkVerts = 0;

    // Iterate over all voxels in the chunk.
    for(GLfloat x = minX; x < maxX; ++x)
    {
        for(GLfloat y = minY; y < maxY; ++y)
        {
            for(GLfloat z = minZ; z < maxZ; ++z)
            {
                [self generateGeometryForSingleBlockWithX:x
                                                        y:y
                                                        z:z
                                                     minX:minX
                                                     minY:minY
                                                     minZ:minZ
                                                     maxX:maxX
                                                     maxY:maxY
                                                     maxZ:maxZ
                                       _texCoordsBuffer:&_texCoordsBuffer
                                           _normsBuffer:&_normsBuffer
                                           _vertsBuffer:&_vertsBuffer];

            }
        }
    }
    
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
}


- (void)generateVBOs
{
    const GLsizeiptr len = 3 * numChunkVerts * sizeof(GLfloat);
    
    [self destroyVBOs];
    
	if(len == 0) {
        return;
    }
    
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
}


- (void)draw
{    
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
	glVertexPointer(3, GL_FLOAT, 0, 0);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
	glNormalPointer(GL_FLOAT, 0, 0);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
	glTexCoordPointer(3, GL_FLOAT, 0, 0);
    
	glDrawArrays(GL_TRIANGLES, 0, numChunkVerts*3);
    
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_VERTEX_ARRAY);
}


- (void)destroyVoxelData
{
    free(voxelData);
    voxelData = NULL;
}


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
}


- (void)dealloc
{
    [self destroyVoxelData];
    [self destroyGeometry];
    [self destroyVBOs];
    
	[super dealloc];
}

@end


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat **_vertsBuffer,
                      GLfloat **_normsBuffer,
                      GLfloat **_texCoordsBuffer)
{
    **_vertsBuffer = vx; (*_vertsBuffer)++;
    **_vertsBuffer = vy; (*_vertsBuffer)++;
    **_vertsBuffer = vz; (*_vertsBuffer)++;
    **_normsBuffer = nx; (*_normsBuffer)++;
    **_normsBuffer = ny; (*_normsBuffer)++;
    **_normsBuffer = nz; (*_normsBuffer)++;
    **_texCoordsBuffer = tx; (*_texCoordsBuffer)++;
    **_texCoordsBuffer = ty; (*_texCoordsBuffer)++;
    **_texCoordsBuffer = tz; (*_texCoordsBuffer)++;
}


// Allocate the largest buffer that could possibly be needed.
static GLfloat * allocateLargestPossibleGeometryBuffer(void)
{
    const size_t maxPossibleVerts = 36 * chunkSizeX * chunkSizeY * chunkSizeZ;
    
    GLfloat *buffer = malloc(sizeof(GLfloat) * maxPossibleVerts * 3);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    bzero(buffer, sizeof(GLfloat) * maxPossibleVerts * 3);
    
    return buffer;
}
