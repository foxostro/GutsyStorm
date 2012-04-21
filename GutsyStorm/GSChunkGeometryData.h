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


@class GSChunkVoxelData;


@interface GSChunkGeometryData : GSChunkData
{
    GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords, vboChunkColors;
    
    NSConditionLock *lockGeometry;
    GLsizei numIndices;
	GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
    GLfloat *colorBuffer;
	GLushort *indexBuffer;
	
@public
    GSVector3 corners[8];
	BOOL visible; // Used by GSChunkStore to note chunks it has determined are visible.
}


- (id)initWithMinP:(GSVector3)_minP
		 voxelData:(GSChunkVoxelData **)voxels;

- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration;

@end
