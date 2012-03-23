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
}

- (void)draw;
- (void)generateVoxelData;
- (void)allocateLargestGeometryBuffers;
- (void)generateGeometry;
- (void)generateVBOs;
- (void)destroyVoxelData;
- (void)destroyVBOs;
- (void)destroyGeometry;

@end
