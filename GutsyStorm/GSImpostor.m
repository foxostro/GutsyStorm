//
//  GSImpostor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import <OpenGL/OpenGL.h>

#import "GSImpostor.h"


extern int checkGLErrors(void);


@interface GSImpostor (Private)

- (void)computeTexCoords;

@end


@implementation GSImpostor

- (id)initWithCamera:(GSCamera *)_camera bounds:(GSAABB *)_bounds
{
    self = [super init];
    if (self) {
        // Initialization code here.
        bzero(verts, sizeof(GSVector3) * 4);
		bzero(texCoords, sizeof(GSVector3) * 4);
		pixelsLeft   = 0;
		pixelsRight  = 0;
		pixelsBottom = 0;
		pixelsTop    = 0;
		shouldForceImpostorUpdate = YES;
		
		bounds = _bounds;
		[bounds retain];
		
		camera = _camera;
		[camera retain];
		
		// Create a rendertexture / FBO for us to render into when updating the impostor.
		// XXX: The FBO wastes a lot of space by only render the object in a portion of it. We use texture coords to select the
		//      desired portion in the billboard. It would be great to find a way to zoom on the entire object when we draw.
		
#if 1
		int viewport[4];
		glGetIntegerv(GL_VIEWPORT, viewport);
		unsigned w = viewport[2];
		unsigned h = viewport[3];
#else
		unsigned w = 256;
		unsigned h = 256;
#endif
		
		renderTexture = [[GSRenderTexture alloc] initWithDimensions:NSMakeRect(0, 0, w, h)];
		assert(checkGLErrors() == 0);
		
		// Need to initially align to the camera so first redraw and first error check is OK.
		glMatrixMode(GL_MODELVIEW);
		glPushMatrix();
		glLoadIdentity();
		[camera submitCameraTransform];
		[self realignToCamera];
		glPopMatrix();
    }
    
    return self;
}


- (void)dealloc
{
	[camera release];
	[bounds release];
}


- (void)realignToCamera
{
	double modelview[16];
	double projection[16];
	GLint viewport[4];
	GSVector3 cameraPos;
	
	assert(checkGLErrors() == 0);
	
	cameraPos = [camera cameraEye];
	
	glGetDoublev(GL_MODELVIEW_MATRIX, modelview);
	glGetDoublev(GL_PROJECTION_MATRIX, projection);
	glGetIntegerv(GL_VIEWPORT, viewport);
	
	// project world-space object AABB vertices into screen-space
	GSVector3 screenVerts[8];
	for(size_t i = 0; i < 8; ++i)
	{
		double x,y,z;
		GSVector3 v = [bounds getVertex:i];
		gluProject(v.x, v.y, v.z, modelview, projection, viewport, &x, &y, &z);
		screenVerts[i] = GSVector3_Make(x, y, z);
	}
	
	GSAABB *billboardBounds = [[GSAABB alloc] initWithVerts:screenVerts numVerts:8];
	
	// Extract the verts (in screen-space) for a quad which will cover the object's AABB exactly.
	GSVector3 screenQuadVerts[4];
	screenQuadVerts[0] = GSVector3_Make(billboardBounds.mins.x, billboardBounds.mins.y, billboardBounds.mins.z);
	screenQuadVerts[1] = GSVector3_Make(billboardBounds.maxs.x, billboardBounds.mins.y, billboardBounds.mins.z);
	screenQuadVerts[2] = GSVector3_Make(billboardBounds.maxs.x, billboardBounds.maxs.y, billboardBounds.mins.z);
	screenQuadVerts[3] = GSVector3_Make(billboardBounds.mins.x, billboardBounds.maxs.y, billboardBounds.mins.z);
	
	pixelsLeft   = billboardBounds.mins.x;
	pixelsRight  = billboardBounds.maxs.x;
	pixelsBottom = billboardBounds.mins.y;
	pixelsTop    = billboardBounds.maxs.y;
	
	[billboardBounds release];
	
	// Project verts back into world-space.
	for(size_t i = 0; i < 4; ++i)
	{
		double x, y, z;
		gluUnProject(screenQuadVerts[i].x, screenQuadVerts[i].y, screenQuadVerts[i].z, modelview, projection, viewport, &x, &y, &z);
		verts[i] = GSVector3_Make(x, y, z);
	}
	
	// Get the center of the quad by taking the average of the vertices.
	center = GSVector3_Make(0, 0, 0);
	for(size_t i = 0; i < 4; ++i)
	{
		center = GSVector3_Add(center, verts[i]);
	}
	center = GSVector3_Scale(center, 0.25);
}


- (void)startUpdateImposter
{
	glMatrixMode(GL_MODELVIEW);
	glPushMatrix();
	glLoadIdentity();
	[camera submitCameraTransform];
	
	[renderTexture startRender];
	
	// Clear the render texture to black with 0 alpha.
	GLfloat originalBgColor[4];
	glGetFloatv(GL_COLOR_CLEAR_VALUE, originalBgColor);
	glClearColor(0.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glClearColor(originalBgColor[0], originalBgColor[1], originalBgColor[2], originalBgColor[3]); // restore
	
	glColor4f(1, 1, 1, 1);
	
	assert(checkGLErrors() == 0);
}


- (void)finishUpdateImposter
{
	[renderTexture finishRender];
	
	glMatrixMode(GL_MODELVIEW);
	glPopMatrix();
	
	[self computeTexCoords];
	
	// Get a vector to the camera. Used later to determine whether an update is needed next.
	cameraVec = GSVector3_Sub([camera cameraEye], center);
	
	shouldForceImpostorUpdate = NO;
}


- (void)draw
{
	glDisable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	
	[renderTexture bind];
	glBegin(GL_QUADS);
	glTexCoord2fv((const float *)&texCoords[0]);
	glVertex3fv((const float *)&verts[0]);
	glTexCoord2fv((const float *)&texCoords[1]);
	glVertex3fv((const float *)&verts[1]);
	glTexCoord2fv((const float *)&texCoords[2]);
	glVertex3fv((const float *)&verts[2]);
	glTexCoord2fv((const float *)&texCoords[3]);
	glVertex3fv((const float *)&verts[3]);
	glEnd();
	[renderTexture unbind];
	
#if 0
	// Draw the outline for debugging purposes.
	glDisable(GL_TEXTURE_2D);
	glDisable(GL_DEPTH_TEST);
	glColor4f(1.0, 0.0, 0.0, 1.0);
	glBegin(GL_LINE_LOOP);
	glVertex3fv((const float *)&verts[0]);
	glVertex3fv((const float *)&verts[1]);
	glVertex3fv((const float *)&verts[2]);
	glVertex3fv((const float *)&verts[3]);
	glEnd();
	glColor4f(1.0, 1.0, 1.0, 1.0);
	glEnable(GL_DEPTH_TEST);
	glEnable(GL_TEXTURE_2D);
#endif
	
	glEnable(GL_LIGHTING);
}


- (BOOL)doesImposterNeedUpdate
{
	if(shouldForceImpostorUpdate) {
		return YES;
	}
	
	GSVector3 newCameraVec = GSVector3_Sub([camera cameraEye], center);
	
	float dot = GSVector3_Dot(GSVector3_Normalize(newCameraVec), GSVector3_Normalize(cameraVec));
	float degrees = (180.0 / M_PI) * acosf(dot);
	
	float degreesThreshold = 1.5f;
	
	return degrees > degreesThreshold;
}


- (void)setNeedsImpostorUpdate:(BOOL)_shouldForceImpostorUpdate
{
	shouldForceImpostorUpdate = _shouldForceImpostorUpdate;
}

@end


@implementation GSImpostor (Private)

- (void)computeTexCoords
{
	// Texture coords are based off the screen position of the object in the *viewport*, which should scale nicely if the render
	// texture is not exactly the same size as the viewport.
	int viewport[4];
	glGetIntegerv(GL_VIEWPORT, viewport);
	unsigned w = viewport[2];
	unsigned h = viewport[3];
	
	float uvLeft = pixelsLeft / w;
	float uvRight = pixelsRight / w;
	float uvBottom = pixelsBottom / h;
	float uvTop = pixelsTop / h;
	
	// Texture coordinate Z is ignored.
	texCoords[0] = GSVector3_Make(uvLeft,  uvBottom, 0);
	texCoords[1] = GSVector3_Make(uvRight, uvBottom, 0);
	texCoords[2] = GSVector3_Make(uvRight, uvTop,    0);
	texCoords[3] = GSVector3_Make(uvLeft,  uvTop,    0);
}

@end
