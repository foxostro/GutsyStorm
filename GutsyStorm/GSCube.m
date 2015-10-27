//
//  GSCube.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import "GSCube.h"
#import "FoxShader.h"
#import "FoxVBOHolder.h"

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
    FoxVBOHolder *_vertexBuffer, *_indexBuffer;
    FoxShader *_shader;
}

- (instancetype)init
{
    @throw nil;
    return nil;
}

- (instancetype)initWithContext:(NSOpenGLContext *)context shader:(FoxShader *)shader
{
    NSParameterAssert(context);
    assert(checkGLErrors() == 0);

    self = [super init];
    if (self) {
        GLuint vboVertexBuffer = 0, vboIndexBuffer = 0;

        glGenBuffers(1, &vboVertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, vboVertexBuffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

        glGenBuffers(1, &vboIndexBuffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vboIndexBuffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

        assert(checkGLErrors() == 0);

        _vertexBuffer = [[FoxVBOHolder alloc] initWithHandle:vboVertexBuffer context:context];
        _indexBuffer = [[FoxVBOHolder alloc] initWithHandle:vboIndexBuffer context:context];
        _shader = shader;
    }

    return self;
}

- (void)drawWithModelViewProjectionMatrix:(matrix_float4x4)mvp
{
    GLsizei count = sizeof(indices)/sizeof(*indices);

    [_shader bind];
    [_shader bindUniformWithMatrix4x4:mvp name:@"mvp"];

    glLineWidth(5.0);
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glEnable(GL_POLYGON_OFFSET_FILL);

    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer.handle);
    glVertexPointer(3, GL_FLOAT, 0, 0);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBuffer.handle);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glDrawElements(GL_TRIANGLE_STRIP, count, GL_UNSIGNED_INT, NULL);
    glDisableClientState(GL_VERTEX_ARRAY);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0); // clear

    glDisable(GL_POLYGON_OFFSET_FILL);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

    [_shader unbind];
}

@end
