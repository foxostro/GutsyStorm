//
//  GSCube.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSCube.h"

static const GLfloat cubeVerts[] = {
	-1, +1, +1,   +1, +1, -1,   -1, +1, -1, // Top Face
	-1, +1, +1,   +1, +1, +1,   +1, +1, -1,
	-1, -1, -1,   +1, -1, -1,   -1, -1, +1, // Bottom Face
	+1, -1, -1,   +1, -1, +1,   -1, -1, +1,
	-1, -1, +1,   +1, +1, +1,   -1, +1, +1, // Front Face
	-1, -1, +1,   +1, -1, +1,   +1, +1, +1,
	-1, +1, -1,   +1, +1, -1,   -1, -1, -1, // Back Face
	+1, +1, -1,   +1, -1, -1,   -1, -1, -1,
	+1, +1, -1,   +1, +1, +1,   +1, -1, +1, // Right Face
	+1, -1, -1,   +1, +1, -1,   +1, -1, +1,
	-1, -1, +1,   -1, +1, +1,   -1, +1, -1, // Left Face
	-1, -1, +1,   -1, +1, -1,   -1, -1, -1
};


static const GLfloat cubeNorms[] = {
    0, +1,  0,    0, +1,  0,    0, +1,  0, // Top Face
    0, +1,  0,    0, +1,  0,    0, +1,  0,
    0, -1,  0,    0, -1,  0,    0, -1,  0, // Bottom Face
    0, -1,  0,    0, -1,  0,    0, -1,  0,
    0,  0, +1,    0,  0, +1,    0,  0, +1, // Front Face
    0,  0, +1,    0,  0, +1,    0,  0, +1,
    0,  0, -1,    0,  0, -1,    0,  0, -1, // Back Face
    0,  0, -1,    0,  0, -1,    0,  0, -1,
	+1,  0,  0,   +1,  0,  0,   +1,  0,  0, // Right Face
	+1,  0,  0,   +1,  0,  0,   +1,  0,  0,
	-1,  0,  0,   -1,  0,  0,   -1,  0,  0, // Left Face
	-1,  0,  0,   -1,  0,  0,   -1,  0,  0
};


static const GLfloat cubeTexCoords[] = {
    1, 1, 0,   0, 0, 0,   1, 0, 0, // Top Face
    1, 1, 0,   0, 1, 0,   0, 0, 0,
    1, 0, 1,   0, 0, 1,   1, 1, 1, // Bottom Face
    0, 0, 1,   0, 1, 1,   1, 1, 1,
    0, 1, 2,   1, 0, 2,   0, 0, 2, // Front Face
    0, 1, 2,   1, 1, 2,   1, 0, 2,
    0, 0, 2,   1, 0, 2,   0, 1, 2, // Back Face
    1, 0, 2,   1, 1, 2,   0, 1, 2,
    0, 0, 2,   1, 0, 2,   1, 1, 2, // Right Face
    0, 1, 2,   0, 0, 2,   1, 1, 2,
    1, 1, 2,   1, 0, 2,   0, 0, 2, // Left Face
    1, 1, 2,   0, 0, 2,   0, 1, 2
};

static const GLsizei numCubeVerts = 12*3;


@implementation GSCube

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        vboCubeVerts = 0;
        vboCubeNorms = 0;
        vboCubeTexCoords = 0;
        [self generateVBO];
    }
    
    return self;
}


// Generates the VBO for the cube.
- (void)generateVBO
{
	glGenBuffers(1, &vboCubeVerts);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeVerts), cubeVerts, GL_STATIC_DRAW);
    
	glGenBuffers(1, &vboCubeNorms);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeNorms);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeNorms), cubeNorms, GL_STATIC_DRAW);
    
	glGenBuffers(1, &vboCubeTexCoords);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeTexCoords);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeTexCoords), cubeTexCoords, GL_STATIC_DRAW);
}


- (void)draw
{	
	glColor4f(1.0, 1.0, 1.0, 1.0);
    
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glVertexPointer(3, GL_FLOAT, 0, 0);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeNorms);
	glNormalPointer(GL_FLOAT, 0, 0);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeTexCoords);
	glTexCoordPointer(3, GL_FLOAT, 0, 0);
    
	glDrawArrays(GL_TRIANGLES, 0, numCubeVerts);
    
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_VERTEX_ARRAY);
}


- (void)dealloc
{
    glDeleteBuffers(1, &vboCubeVerts);
    glDeleteBuffers(1, &vboCubeNorms);
    glDeleteBuffers(1, &vboCubeTexCoords);
    
    vboCubeVerts = 0;
    vboCubeNorms = 0;
    vboCubeTexCoords = 0;
    
	[super dealloc];
}

@end
