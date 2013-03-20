//
//  GSChunkVBOs.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKVector3.h>
#import <GLKit/GLKQuaternion.h>
#import "GSGridItem.h"
#import "GSChunkVBOs.h"
#import "GSIntegerVector3.h"
#import "GSChunkGeometryData.h"
#import "GSVertex.h"


#define SIZEOF_STRUCT_ARRAY_ELEMENT(t, m) sizeof(((t*)0)->m[0])


extern int checkGLErrors(void);
static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo);


// Make sure the number of indices can be stored in the type used for the shared index buffer.
static const GLsizei SHARED_INDEX_BUFFER_LEN = 200000; // NOTE: use a different value when index_t is GLushort.
typedef GLint index_t;


@interface GSChunkVBOs ()

+ (index_t *)sharedIndexBuffer;

@end


@implementation GSChunkVBOs
{
    GLsizei _numIndicesForDrawing;
    GLuint _vbo;
    NSOpenGLContext *_glContext;
}

@synthesize minP;

+ (index_t *)sharedIndexBuffer
{
    static dispatch_once_t onceToken;
    static index_t *buffer;

    dispatch_once(&onceToken, ^{
        // Take the indices array and generate a raw index buffer that OpenGL can consume.
        buffer = malloc(sizeof(index_t) * SHARED_INDEX_BUFFER_LEN);
        if(!buffer) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
        }

        for(GLsizei i = 0; i < SHARED_INDEX_BUFFER_LEN; ++i)
        {
            buffer[i] = i; // a simple linear walk
        }
    });

    return buffer;
}

- (id)initWithChunkGeometry:(GSChunkGeometryData *)geometry
                  glContext:(NSOpenGLContext *)context
{
    assert(geometry);
    assert(context);
    
    if(self = [super init]) {
        struct vertex *vertsBuffer = NULL;
        _numIndicesForDrawing = [geometry copyVertsToBuffer:&vertsBuffer];
        _glContext = context;
        _vbo = 0;
        minP = geometry.minP;

        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
        {
            glGenBuffers(1, &_vbo);
            glBindBuffer(GL_ARRAY_BUFFER, _vbo);
            glBufferData(GL_ARRAY_BUFFER, _numIndicesForDrawing * sizeof(struct vertex), vertsBuffer, GL_STATIC_DRAW);
            glBindBuffer(GL_ARRAY_BUFFER, 0);
        }
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
    }

    return self;
}

- (void)dealloc
{
    dispatch_async(dispatch_get_main_queue(), ^{
        syncDestroySingleVBO(_glContext, _vbo);
    });
}

- (void)draw
{
    if(!_vbo) {
        return;
    }

    if(_numIndicesForDrawing <= 0) {
        return;
    }

    // TODO: use VAOs

    const index_t * const indices = [GSChunkVBOs sharedIndexBuffer]; // TODO: index buffer object

    assert(checkGLErrors() == 0);
    assert(_numIndicesForDrawing < SHARED_INDEX_BUFFER_LEN);
    assert(indices);

    glBindBuffer(GL_ARRAY_BUFFER, _vbo);

    // Verify that vertex attribute formats are consistent with in-memory storage.
    assert(sizeof(GLfloat) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, position));
    assert(sizeof(GLbyte)  == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, normal));
    assert(sizeof(GLshort) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, texCoord));
    assert(sizeof(GLubyte) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, color));

    const GLvoid *offsetVertex   = (const GLvoid *)offsetof(struct vertex, position);
    const GLvoid *offsetNormal   = (const GLvoid *)offsetof(struct vertex, normal);
    const GLvoid *offsetTexCoord = (const GLvoid *)offsetof(struct vertex, texCoord);
    const GLvoid *offsetColor    = (const GLvoid *)offsetof(struct vertex, color);

    const GLsizei stride = sizeof(struct vertex);
    glVertexPointer(  3, GL_FLOAT,         stride, offsetVertex);
    glNormalPointer(     GL_BYTE,          stride, offsetNormal);
    glTexCoordPointer(3, GL_SHORT,         stride, offsetTexCoord);
    glColorPointer(   4, GL_UNSIGNED_BYTE, stride, offsetColor);

    GLenum indexEnum;
    if(2 == sizeof(index_t)) {
        indexEnum = GL_UNSIGNED_SHORT;
    } else if(4 == sizeof(index_t)) {
        indexEnum = GL_UNSIGNED_INT;
    } else {
        assert(!"I don't know the GLenum to use with index_t.");
    }

    glDrawElements(GL_QUADS, _numIndicesForDrawing, indexEnum, indices);
    assert(checkGLErrors() == 0);
}

@end


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo)
{
    assert(context);
    if(vbo) {
        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
        glDeleteBuffers(1, &vbo);
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
    }
}