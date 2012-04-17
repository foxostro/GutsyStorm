//
//  GSChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>
#import "GSChunkData.h"

@class GSChunkVoxelData; // forward delcaration

@interface GSChunkGeometryData : GSChunkData
{
    GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords;
    
    NSConditionLock *lockGeometry;
    GLsizei numIndices;
	GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
	GLushort *indexBuffer;
	
@public
    GSVector3 corners[8];
	BOOL visible;
}

- (id)initWithMinP:(GSVector3)_minP
		 voxelData:(GSChunkVoxelData *)voxels;
- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration;

@end
