//
//  GutsyStormOpenGLView.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import "GutsyStormOpenGLView.h"

GLfloat cubeVerts[] = {
	-1, +1, +1,   +1, +1, -1,   -1, +1, -1, // Top Face
	-1, +1, +1,   +1, +1, +1,   +1, +1, -1,
	-1, -1, -1,   +1, -1, -1,   -1, -1, +1, // Bottom Face
	+1, -1, -1,   +1, -1, +1,   -1, -1, +1,
	-1, -1, +1,   +1, +1, +1,   -1, +1, +1, // Front Face
	-1, -1, +1,   +1, -1, +1,   +1, +1, +1,
	-1, +1, -1,   +1, +1, -1,   -1, -1, -1, // Back Face
	+1, +1, -1,   +1, -1, -1,   -1, -1, -1,
	+1, +1, -1,   +1, +1, +1,   +1, -1, +1, // Right Face
	+1, -1, -1,   +1, +1, -1,   +1, -1, +1,
	-1, -1, +1,   -1, +1, +1,   -1, +1, -1, // Left Face
	-1, -1, +1,   -1, +1, -1,   -1, -1, -1
};

GLsizei numCubeVerts = 12*3;


int checkGLErrors(void);


@implementation GutsyStormOpenGLView

- (void)prepareOpenGL
{
	[[self openGLContext] makeCurrentContext];
	assert(checkGLErrors() == 0);
	
	glClearColor(0.2, 0.4, 0.5, 1.0);
	
	glDisable(GL_LIGHTING);
	glEnable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
			
	glGenBuffers(1, &vboCubeVerts);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeVerts), cubeVerts, GL_STATIC_DRAW);
	assert(checkGLErrors() == 0);
	NSLog(@"Generated the VBO.");
}

-(void)awakeFromNib
{
	NSLog(@"awakeFromNib");
	vboCubeVerts = 0;
}

// Draw a white cube at the specified position.
- (void)drawDebugCubeAtX:(float)x
					   Y:(float)y
					   Z:(float)z
{
	assert(checkGLErrors() == 0);
	
	glPushMatrix();
	glTranslatef(x, y, z);
	
	glEnableClientState(GL_VERTEX_ARRAY);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glVertexPointer(3, GL_FLOAT, 0, 0);
	glDrawArrays(GL_TRIANGLES, 0, numCubeVerts);
	glDisableClientState(GL_VERTEX_ARRAY);
	
	glPopMatrix();
	 
	assert(checkGLErrors() == 0);
}

- (void)reshape
{
	NSLog(@"reshape");
	NSRect r = [self convertRectToBase:[self bounds]];
	glViewport(0, 0, r.size.width, r.size.height);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	gluPerspective(60.0, r.size.width/r.size.height, 0.1, 400.0);
	glMatrixMode(GL_MODELVIEW);
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSLog(@"drawRect");
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	[self drawDebugCubeAtX:0.0 Y:0.0 Z:-5.0];
	glFlush();
}

@end


int checkGLErrors(void)
{
	int errCount = 0;
	
	for(GLenum currError = glGetError(); currError != GL_NO_ERROR; currError = glGetError())
	{
		NSLog(@"OpenGL Error: %s", (const char *)gluErrorString(currError));
		++errCount;
	}

	return errCount;
}
