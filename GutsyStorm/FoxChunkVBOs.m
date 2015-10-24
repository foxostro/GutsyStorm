//
//  FoxChunkVBOs.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGridItem.h"
#import "FoxChunkVBOs.h"
#import "FoxIntegerVector3.h"
#import "FoxChunkGeometryData.h"
#import "GSBoxedTerrainVertex.h"
#import "FoxVBOHolder.h"


#define SIZEOF_STRUCT_ARRAY_ELEMENT(t, m) sizeof(((t*)0)->m[0])


extern int checkGLErrors(void);


// Make sure the number of indices can be stored in the type used for the shared index buffer.
// NOTE: use a different value when index_t is GLushort.
static const GLsizei SHARED_INDEX_BUFFER_LEN = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * 36;
typedef GLuint index_t;


@implementation FoxChunkVBOs
{
    GLsizei _numIndicesForDrawing;
    FoxVBOHolder *_vbo, *_ibo;
    NSOpenGLContext *_glContext;
}

@synthesize minP;

+ (FoxVBOHolder *)sharedIndexBufferObject
{
    static dispatch_once_t onceToken;
    static FoxVBOHolder *iboHolder;

    dispatch_once(&onceToken, ^{
        // Take the indices array and generate a raw index buffer that OpenGL can consume.
        index_t *buffer = malloc(sizeof(index_t) * SHARED_INDEX_BUFFER_LEN);
        if(!buffer) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
        }

        for(GLsizei i = 0; i < SHARED_INDEX_BUFFER_LEN; ++i)
        {
            buffer[i] = i; // a simple linear walk
        }
        
        GLuint ibo = 0;
        
        glGenBuffers(1, &ibo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, SHARED_INDEX_BUFFER_LEN * sizeof(index_t), buffer, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        assert(checkGLErrors() == 0);
        
        iboHolder = [[FoxVBOHolder alloc] initWithHandle:ibo context:[NSOpenGLContext currentContext]];
    });

    return iboHolder;
}

- (instancetype)initWithChunkGeometry:(FoxChunkGeometryData *)geometry
                            glContext:(NSOpenGLContext *)context
{
    assert(geometry);
    assert(context);
    
    if(self = [super init]) {
        struct GSTerrainVertex *vertsBuffer = NULL;
        _numIndicesForDrawing = [geometry copyVertsToBuffer:&vertsBuffer];
        _glContext = context;
        minP = geometry.minP;
        
        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
        
        GLuint vbo = 0;
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, _numIndicesForDrawing * sizeof(struct GSTerrainVertex), vertsBuffer, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);

        _vbo = [[FoxVBOHolder alloc] initWithHandle:vbo context:context];
        free(vertsBuffer);

        _ibo = [[self class] sharedIndexBufferObject];
        
        assert(checkGLErrors() == 0);
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
    }

    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // All FoxChunkVBO objects are immutable, so return self instead of deep copying.
}

- (void)draw
{
    // TODO: use VAOs

    assert(checkGLErrors() == 0);
    assert(_numIndicesForDrawing < SHARED_INDEX_BUFFER_LEN);

    glBindBuffer(GL_ARRAY_BUFFER, _vbo.handle);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ibo.handle);
    
#ifndef NDEBUG
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Verify that vertex attribute formats are consistent with in-memory storage.
        assert(sizeof(GLfloat) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct GSTerrainVertex, position));
        assert(sizeof(GLbyte)  == SIZEOF_STRUCT_ARRAY_ELEMENT(struct GSTerrainVertex, normal));
        assert(sizeof(GLshort) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct GSTerrainVertex, texCoord));
        assert(sizeof(GLubyte) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct GSTerrainVertex, color));
    });
#endif

    const GLvoid *offsetVertex   = (const GLvoid *)offsetof(struct GSTerrainVertex, position);
    const GLvoid *offsetNormal   = (const GLvoid *)offsetof(struct GSTerrainVertex, normal);
    const GLvoid *offsetTexCoord = (const GLvoid *)offsetof(struct GSTerrainVertex, texCoord);
    const GLvoid *offsetColor    = (const GLvoid *)offsetof(struct GSTerrainVertex, color);

    const GLsizei stride = sizeof(struct GSTerrainVertex);
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
    
    glDrawElements(GL_TRIANGLES, _numIndicesForDrawing, indexEnum, NULL);

    assert(checkGLErrors() == 0);
}

@end