//
//  GSCube.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSCube.h"
#import "GSVBOHolder.h"

#import <OpenGL/gl.h>

extern int checkGLErrors(void);

static const float L = 0.5;

static const GLuint indices[] = {
    3, 2, 6, 7, 4, 2, 0, 3, 1, 6, 5, 4, 1, 0
};

static const GLfloat vertices[] = {
    -L,  L, -L,
     L,  L, -L,
    -L,  L,  L,
     L,  L,  L,
    -L, -L, -L,
     L, -L, -L,
     L, -L,  L,
    -L, -L,  L,
};


@implementation GSCube
{
    GSVBOHolder *_vertexBuffer, *_indexBuffer;
}

- (instancetype)init
{
    @throw nil;
    return nil;
}

- (instancetype)initWithContext:(NSOpenGLContext *)context
{
    NSParameterAssert(context);

    self = [super init];
    if (self) {
        GLuint vboVertexBuffer = 0, vboIndexBuffer = 0;

        checkGLErrors();

        glGenBuffers(1, &vboVertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, vboVertexBuffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

        glGenBuffers(1, &vboIndexBuffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboIndexBuffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);
        
        
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        checkGLErrors();

        _vertexBuffer = [[GSVBOHolder alloc] initWithHandle:vboVertexBuffer context:context];
        _indexBuffer = [[GSVBOHolder alloc] initWithHandle:vboIndexBuffer context:context];
    }

    return self;
}

- (void)draw
{
    GLsizei count = sizeof(indices)/sizeof(*indices);

    glLineWidth(2.0);

    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glEnableClientState(GL_VERTEX_ARRAY);

    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer.handle);
    glVertexPointer(3, GL_FLOAT, 0, 0);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBuffer.handle);
    glDrawElements(GL_TRIANGLE_STRIP, count, GL_UNSIGNED_INT, NULL);

    glDisableClientState(GL_VERTEX_ARRAY);
    glDisable(GL_POLYGON_OFFSET_FILL);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0); // clear
}

@end
