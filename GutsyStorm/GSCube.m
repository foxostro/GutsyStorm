//
//  GSCube.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSCube.h"

static const float L = 0.5;

static const GLfloat cubeVerts[] = {
    // Top Face
    -L, +L, -L,
    -L, +L, +L,
    +L, +L, +L,
    +L, +L, -L,

    // Bottom Face
    -L, -L, -L,
    +L, -L, -L,
    +L, -L, +L,
    -L, -L, +L,
    
    // Back Face (+Z)
    -L, -L, +L,
    +L, -L, +L,
    +L, +L, +L,
    -L, +L, +L,
    
    // Front Face (-Z)
    -L, -L, -L,
    -L, +L, -L,
    +L, +L, -L,
    +L, -L, -L,
    
    // Right Face
    +L, -L, -L,
    +L, +L, -L,
    +L, +L, +L,
    +L, -L, +L,
    
    // Left Face
    -L, -L, -L,
    -L, -L, +L,
    -L, +L, +L,
    -L, +L, -L,
};

static const GLsizei numCubeVerts = 12*3;


@implementation GSCube
{
	GLuint _vboCubeVerts, _vboCubeNorms, _vboCubeTexCoords;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _vboCubeVerts = 0;
        _vboCubeNorms = 0;
        _vboCubeTexCoords = 0;
        [self generateVBO];
    }
    
    return self;
}


// Generates the VBO for the cube.
- (void)generateVBO
{
    glGenBuffers(1, &_vboCubeVerts);
    glBindBuffer(GL_ARRAY_BUFFER, _vboCubeVerts);
    glBufferData(GL_ARRAY_BUFFER, sizeof(cubeVerts), cubeVerts, GL_STATIC_DRAW);
}


- (void)draw
{
    glPushMatrix();
    
    glLineWidth(2.0);
    
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glEnableClientState(GL_VERTEX_ARRAY);
    
    glBindBuffer(GL_ARRAY_BUFFER, _vboCubeVerts);
    glVertexPointer(3, GL_FLOAT, 0, 0);
    
    glDrawArrays(GL_QUADS, 0, numCubeVerts);
    
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisable(GL_POLYGON_OFFSET_FILL);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    
    
    glPopMatrix();
}


- (void)dealloc
{
    // Can't reference array from within a block so use some temporary variables.
    GLuint buffer1 = _vboCubeVerts;
    GLuint buffer2 = _vboCubeNorms;
    GLuint buffer3 = _vboCubeTexCoords;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        glDeleteBuffers(1, &buffer1);
        glDeleteBuffers(1, &buffer2);
        glDeleteBuffers(1, &buffer3);
    });
    
    [super dealloc];
}

@end
