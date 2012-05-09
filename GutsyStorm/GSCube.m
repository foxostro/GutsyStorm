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
    -L, +L, -L,   +L, +L, -L,   -L, +L, -L, // Top Face
    -L, +L, +L,   +L, +L, +L,   +L, +L, -L,
    -L, -L, -L,   +L, -L, -L,   -L, -L, +L, // Bottom Face
    +L, -L, -L,   +L, -L, +L,   -L, -L, +L,
    -L, -L, +L,   +L, +L, +L,   -L, +L, +L, // Front Face
    -L, -L, +L,   +L, -L, +L,   +L, +L, +L,
    -L, +L, -L,   +L, +L, -L,   -L, -L, -L, // Back Face
    +L, +L, -L,   +L, -L, -L,   -L, -L, -L,
    +L, +L, -L,   +L, +L, +L,   +L, -L, +L, // Right Face
    +L, -L, -L,   +L, +L, -L,   +L, -L, +L,
    -L, -L, +L,   -L, +L, +L,   -L, +L, -L, // +Left Face
    -L, -L, +L,   -L, +L, -L,   -L, -L, -L
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
}


- (void)draw
{
    glPushMatrix();
    
    glLineWidth(3.0);
    
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glEnableClientState(GL_VERTEX_ARRAY);
    
    glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
    glVertexPointer(3, GL_FLOAT, 0, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, numCubeVerts);
    
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisable(GL_POLYGON_OFFSET_FILL);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    
    
    glPopMatrix();
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
