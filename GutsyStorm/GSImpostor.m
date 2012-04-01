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


static const float EPSILON = 1e-8;


extern int checkGLErrors(void);


@interface GSImpostor (Private)

- (float)dotProductWithCameraVec;
- (void)setupProjectionMatrix; // Loads the desired projection matrix into the current matrix in OpenGL.

@end


@implementation GSImpostor

- (id)initWithCamera:(GSCamera *)_camera bounds:(GSAABB *)_bounds
{
    self = [super init];
    if (self) {
        // Initialization code here.
		bounds = _bounds;
		[bounds retain];
		
		modelViewMatrix = GSMatrix4_Identity();
		
		// XXX: Should try to determine a good size for the render texture instead of always using 256x256.
		renderTexture = [[GSRenderTexture alloc] initWithDimensions:NSMakeRect(0, 0, 256, 256)];
		assert(checkGLErrors() == 0);
		
		camera = _camera;
		[camera retain];
		
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
	
	glGetFloatv(GL_MODELVIEW_MATRIX, modelViewMatrix.m);
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
	
	// Extract the verts (in screen-space) for a quad which will cover the object's AABB exactly.
	GSAABB *billboardBounds = [[GSAABB alloc] initWithVerts:screenVerts numVerts:8];
	GSVector3 screenQuadVerts[4];
	screenQuadVerts[0] = GSVector3_Make(billboardBounds.mins.x, billboardBounds.mins.y, billboardBounds.mins.z);
	screenQuadVerts[1] = GSVector3_Make(billboardBounds.maxs.x, billboardBounds.mins.y, billboardBounds.mins.z);
	screenQuadVerts[2] = GSVector3_Make(billboardBounds.maxs.x, billboardBounds.maxs.y, billboardBounds.mins.z);
	screenQuadVerts[3] = GSVector3_Make(billboardBounds.mins.x, billboardBounds.maxs.y, billboardBounds.mins.z);
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
	
	// Get the unit-vector to the camera. Used later to determine whether an update is needed.
	cameraVec = GSVector3_Normalize(GSVector3_Sub(cameraPos, center));
}


- (BOOL)startUpdateImposter
{
	/*if([self dotProductWithCameraVec] < 0.0) {
		return NO;
	}*/
	
	glMatrixMode(GL_PROJECTION);
	glPushMatrix();
	[self setupProjectionMatrix];

	glMatrixMode(GL_MODELVIEW);
	glPushMatrix();
	glLoadIdentity();
	[camera submitCameraTransform];
	
	[renderTexture startRender];
	
	// Clear the render texture.
	glClearColor(0.2, 0.4, 0.5, 0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glColor4f(1, 1, 1, 1);
	
	assert(checkGLErrors() == 0);
	
	return YES;
}


- (void)finishUpdateImposter
{
	[renderTexture finishRender];
	
	glMatrixMode(GL_MODELVIEW);
	glPopMatrix();
	
	glMatrixMode(GL_PROJECTION);
	glPopMatrix();
	
	glMatrixMode(GL_MODELVIEW);
}


- (void)draw
{
	glDisable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	
	[renderTexture bind];
	glBegin(GL_QUADS);
	glTexCoord2f(0, 0);
	glVertex3fv((const float *)&verts[0]);
	glTexCoord2f(1, 0);
	glVertex3fv((const float *)&verts[1]);
	glTexCoord2f(1, 1);
	glVertex3fv((const float *)&verts[2]);
	glTexCoord2f(0, 1);
	glVertex3fv((const float *)&verts[3]);
	glEnd();
	[renderTexture unbind];
	
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
	
	glEnable(GL_LIGHTING);
}


- (BOOL)doesImposterNeedUpdate
{
	return [self dotProductWithCameraVec] < 0.99999;
}

@end


@implementation GSImpostor (Private)


- (void)setupProjectionMatrix
{
	GSVector3 cameraPos = [camera cameraEye];
	
	assert(checkGLErrors() == 0);
	
#if 1
	// Setup a projection matrix so that the object completely fills the render texture.
	// The clipping planes for glFrustum are in eye-space so build a bounds AABB in eye-space and use that to construct the planes.
	GSVector3 boundsVertsInEyeSpace[8];
	for(size_t i = 0; i < 8; ++i)
	{
		boundsVertsInEyeSpace[i] = GSMatrix4_ProjVec3(modelViewMatrix, [bounds getVertex:i]);
	}
	
	GSAABB *eyeSpaceBounds = [[GSAABB alloc] initWithVerts:boundsVertsInEyeSpace numVerts:8];
	
	float left   = [eyeSpaceBounds mins].x;
	float right  = [eyeSpaceBounds maxs].x;
	float bottom = [eyeSpaceBounds mins].y;
	float top    = [eyeSpaceBounds maxs].y;
	
	float depthInEyeSpace = GSVector3_Length(GSVector3_Sub([eyeSpaceBounds maxs], [eyeSpaceBounds mins]));
	float near = GSVector3_Length(GSVector3_Sub(center, cameraPos));
	float far = near + depthInEyeSpace;
	
	[eyeSpaceBounds release];
	
	if(fabs(right - left) < EPSILON) {
		[NSException raise:@"Invalid Value" format:@"Left and Right must not be equal: left=%f, right=%f", left, right];
	}
	
	if(fabs(top - bottom) < EPSILON) {
		[NSException raise:@"Invalid Value" format:@"Bottom and Top must not be equal: bottom=%f, top=%f", bottom, top];
	}
	
	if(near < 0) {
		[NSException raise:@"Invalid Value" format:@"Near must be positive: near=%f", near];
	}
	
	if(far < 0) {
		[NSException raise:@"Invalid Value" format:@"Far must be positive: far=%f", far];
	}
	
	glLoadIdentity();
	glFrustum(left, right, bottom, top, near, far);
#else
	float nearPlane = GSVector3_Length(GSVector3_Sub(center, cameraPos));
	float farPlane = nearPlane + GSVector3_Length(GSVector3_Sub([bounds maxs], [bounds mins]));
	
	// calculate the width and height of our imposter's vertices
	float w = GSVector3_Length(GSVector3_Sub(verts[1], verts[0]));
	float h = GSVector3_Length(GSVector3_Sub(verts[3], verts[0]));
	
	// setup a projection matrix with near plane points exactly covering the object
	glLoadIdentity();
	glFrustum(-w/2,w/2,-h/2,h/2,nearPlane,farPlane);
#endif
	
	assert(checkGLErrors() == 0);
	
}


- (float)dotProductWithCameraVec
{
	GSVector3 newCameraVec = GSVector3_Normalize(GSVector3_Sub([camera cameraEye], center));
	return GSVector3_Dot(newCameraVec, cameraVec);
}

@end
