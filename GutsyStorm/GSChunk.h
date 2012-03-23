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
- (void)generateGeometryForSingleBlockWithX:(GLfloat)x
                                          y:(GLfloat)y
                                          z:(GLfloat)z
                                       minX:(GLfloat)minX
                                       minY:(GLfloat)minY
                                       minZ:(GLfloat)minZ
                                       maxX:(GLfloat)maxX
                                       maxY:(GLfloat)maxY
                                       maxZ:(GLfloat)maxZ
                           _texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                               _normsBuffer:(GLfloat **)_normsBuffer
                               _vertsBuffer:(GLfloat **)_vertsBuffer;

@end
