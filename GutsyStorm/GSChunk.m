//
//  GSChunk.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunk.h"

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
        //[self generateGeometry];
        //[self generateVBO];
    }
    
    return self;
}


- (void)generateVoxelData
{
    assert(!"unimplemented");
}


// Generates verts, norms, and texCoords buffers from voxelData
- (void)generateGeometry
{
    assert(!"unimplemented");
}


- (void)generateVBO
{
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
    
	glDrawArrays(GL_TRIANGLES, 0, numChunkVerts);
    
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_VERTEX_ARRAY);
}


- (void)dealloc
{
    glDeleteBuffers(1, &vboChunkVerts);
    glDeleteBuffers(1, &vboChunkNorms);
    glDeleteBuffers(1, &vboChunkTexCoords);
    
    free(vertsBuffer);
    free(normsBuffer);
    free(texCoordsBuffer);
    
	[super dealloc];
}

@end
