//
//  GSChunk.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

#import "GSVector3.h"

@interface GSChunk : NSObject
{
	GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords;
    GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
    BOOL *voxelData;
}

- (void)draw;


// Internals

- (void)generateVoxelData;
- (void)generateGeometry;
- (void)generateVBOs;
- (void)destroyVoxelData;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (BOOL)getVoxelValueWithX:(size_t)x y:(size_t)y z:(size_t)z;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                       minP:(GSVector3)minP
                                       maxP:(GSVector3)maxP
                           _texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                               _normsBuffer:(GLfloat **)_normsBuffer
                               _vertsBuffer:(GLfloat **)_vertsBuffer;

@end
