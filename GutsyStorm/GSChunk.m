//
//  GSChunk.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunk.h"

const size_t chunkSizeX = 16;
const size_t chunkSizeY = 16;
const size_t chunkSizeZ = 16;


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GLfloat **_vertsBuffer,
                      GLfloat **_normsBuffer,
                      GLfloat **_texCoordsBuffer);


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
        
        //[self generateVoxelData];
        [self generateGeometry];
        [self generateVBOs];
    }
    
    return self;
}


- (void)generateVoxelData
{
    assert(!"unimplemented");
    [self destroyVoxelData];
}


- (void)allocateLargestGeometryBuffers
{
    // TODO: This is 288MB of storage for each buffer. Only allocate what will be necessary.
    const size_t maxPossibleVerts = sizeof(GLfloat) * 36 * chunkSizeX * chunkSizeY * chunkSizeZ;
    
    // Allocate the largest buffers for geometry that could possibly be needed.
    vertsBuffer = malloc(maxPossibleVerts * 3);
    if(!vertsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allociating chunk vertsBuffer."];
    }
    bzero(vertsBuffer, maxPossibleVerts);
    
    normsBuffer = malloc(maxPossibleVerts * 3);
    if(!normsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allociating chunk normsBuffer."];
    }
    bzero(normsBuffer, maxPossibleVerts);
    
    texCoordsBuffer = malloc(maxPossibleVerts * 3);
    if(!texCoordsBuffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allociating chunk texCoordsBuffer."];
    }
    bzero(texCoordsBuffer, maxPossibleVerts);
}


// Generates verts, norms, and texCoords buffers from voxelData
- (void)generateGeometry
{
    [self destroyGeometry];
    
    [self allocateLargestGeometryBuffers];
    
    const GLfloat L = 0.5f;
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    
    GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
    
    numChunkVerts = 0;

    // Iterate over all voxels in the chunk.
    for(GLfloat x = 0; x < (GLfloat)chunkSizeX; ++x)
    {
        for(GLfloat y = 0; y < (GLfloat)chunkSizeY; ++y)
        {
            for(GLfloat z = 0; z < (GLfloat)chunkSizeZ; ++z)
            {
                // Top Face
                if(YES) { // not (y+1<maxY and voxelData.get(x-minX, y-minY+1, z-minZ)):
                    // This face is exposed to air on the top so use page 1 for the other sides of the block.
                    GLfloat page = grass;
                    
                    // Face 1
                    addVertex(x-L, y+L, z+L,
                              0, 1, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z-L,
                              0, 1, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y+L, z-L,
                              0, 1, 0,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x-L, y+L, z+L,
                              0, 1, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z+L,
                              0, 1, 0,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z-L,
                              0, 1, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }

                // Bottom Face
                if(YES) { // not (y-1>=minY and voxelData.get(x-minX, y-minY-1, z-minZ)):
                    // This face is always dirt.
                    GLfloat page = dirt;
                    
                    // Face 1
                    addVertex(x-L, y-L, z-L,
                              0, -1, 0,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z-L,
                              0, -1, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y-L, z+L,
                              0, -1, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x+L, y-L, z-L,
                              0, -1, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z+L,
                              0, -1, 0,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y-L, z+L,
                              0, -1, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }

                // Front Face
                if(YES) { // not (z+1<maxZ and voxelData.get(x-minX, y-minY, z-minZ+1)):
                    GLfloat page = side;
                    
                    // Face 1
                    addVertex(x-L, y-L, z+L,
                              0, 0, 1,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z+L,
                              0, 0, 1,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y+L, z+L,
                              0, 0, 1,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x-L, y-L, z+L,
                              0, 0, 1,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z+L,
                              0, 0, 1,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z+L,
                              0, 0, 1,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }

                // Back Face
                if(YES) { // not (z-1>=minZ and voxelData.get(x-minX, y-minY, z-minZ-1)):
                    GLfloat page = side;
                    
                    // Face 1
                    addVertex(x-L, y+L, z-L,
                              0, 0, -1,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z-L,
                              0, 0, -1,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y-L, z-L,
                              0, 0, -1,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x+L, y+L, z-L,
                              0, 0, -1,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z-L,
                              0, 0, -1,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y-L, z-L,
                              0, 0, -1,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }

                // Right Face
                if(YES) { // not (x+1<maxX and voxelData.get(x-minX+1, y-minY, z-minZ)):
                    GLfloat page = side;
                    
                    // Face 1
                    addVertex(x+L, y+L, z-L,
                              1, 0, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z+L,
                              1, 0, 0,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z+L,
                              1, 0, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x+L, y-L, z-L,
                              1, 0, 0,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y+L, z-L,
                              1, 0, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x+L, y-L, z+L,
                              1, 0, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }

                // Left Face
                if(YES) { // not (x-1>=minX and voxelData.get(x-minX-1, y-minY, z-minZ)):
                    GLfloat page = side;
                    
                    // Face 1
                    addVertex(x-L, y-L, z+L,
                              -1, 0, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y+L, z+L,
                              -1, 0, 0,
                              1, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y+L, z-L,
                              -1, 0, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    // Face 2
                    addVertex(x-L, y-L, z+L,
                              -1, 0, 0,
                              1, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y+L, z-L,
                              -1, 0, 0,
                              0, 1, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                    
                    addVertex(x-L, y-L, z-L,
                              -1, 0, 0,
                              0, 0, page,
                              &_vertsBuffer,
                              &_normsBuffer,
                              &_texCoordsBuffer);
                    numChunkVerts++;
                }
            } // loop over z
        } // loop over y
    } // loop over x
    
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
    assert(!"unimplemented");
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
