//
//  GSOpenGLView.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <ApplicationServices/ApplicationServices.h>
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import "GSOpenGLView.h"


static const GLfloat cubeVerts[] = {
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

static const GLsizei numCubeVerts = 12*3;


int checkGLErrors(void);


@implementation GSOpenGLView

- (void)enableVSync
{
	// enable vsync
	  GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

}


- (void)prepareOpenGL
{
	[[self openGLContext] makeCurrentContext];
	assert(checkGLErrors() == 0);
	
	glClearColor(0.2, 0.4, 0.5, 1.0);
	
	glDisable(GL_LIGHTING);
	glEnable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
			
	[self generateVBOForDebugCube];
	[self enableVSync];

	assert(checkGLErrors() == 0);
}


-(void)awakeFromNib
{
	NSLog(@"awakeFromNib");
	
	vboCubeVerts = 0;
	cubeRotY = 0.0;
	cubeRotSpeed = 0.0;
	prevFrameTime = CFAbsoluteTimeGetCurrent();
	keysDown = [[NSMutableDictionary alloc] init];
	
	// Reset mouse input mechanism for camera.
	mouseSensitivity = 0.2;
	mouseDeltaX = 0;
	mouseDeltaY = 0;
	[self setMouseAtCenter];
	
	// Set up the default camera.
	cameraSpeed = 5.0;
	cameraRotSpeed = 1.0;
	cameraEye = GSVector3_Make(0.0f, 0.0f, 0.0f);
	cameraCenter = GSVector3_Make(0.0f, 0.0f, -1.0f);
	cameraUp = GSVector3_Make(0.0f, 1.0f, 0.0f);
	cameraRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), 0);
	[self updateCameraLookVectors];
	
	// Register with window to accept user input.
	[[self window] makeFirstResponder: self];
	[[self window] setAcceptsMouseMovedEvents: YES];
	
	// Register a timer to drive the game loop.
	renderTimer = [NSTimer timerWithTimeInterval:0.001   // a 1ms time interval
										  target:self
										selector:@selector(timerFired:)
										userInfo:nil
										 repeats:YES];
				   
	[[NSRunLoop currentRunLoop] addTimer:renderTimer 
								 forMode:NSDefaultRunLoopMode];
	
	[[NSRunLoop currentRunLoop] addTimer:renderTimer 
								 forMode:NSEventTrackingRunLoopMode]; // Ensure timer fires during resize
}


// Generates the VBO for the debug cube.
- (void)generateVBOForDebugCube
{
	glGenBuffers(1, &vboCubeVerts);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeVerts), cubeVerts, GL_STATIC_DRAW);
	
	assert(checkGLErrors() == 0);
}


// Draw a white cube
- (void)drawDebugCube
{
	assert(checkGLErrors() == 0);
	
	glEnableClientState(GL_VERTEX_ARRAY);
	glColor4f(1.0, 1.0, 1.0, 1.0);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glVertexPointer(3, GL_FLOAT, 0, 0);
	glDrawArrays(GL_TRIANGLES, 0, numCubeVerts);
	glDisableClientState(GL_VERTEX_ARRAY);
	 
	assert(checkGLErrors() == 0);
}


- (BOOL) acceptsFirstResponder
{
	return YES;
}


- (void)mouseMoved: (NSEvent *)theEvent
{
	CGGetLastMouseDelta(&mouseDeltaX, &mouseDeltaY);	
	[self setMouseAtCenter];
}


// Reset mouse to the center of the view so it can't leave the window.
- (void) setMouseAtCenter
{
	NSRect bounds = [self bounds];
	CGPoint viewCenter;
	viewCenter.x = bounds.origin.x + bounds.size.width / 2;
	viewCenter.x = bounds.origin.y + bounds.size.height / 2;
	CGWarpMouseCursorPosition(viewCenter);
}


- (void) keyDown:(NSEvent *)theEvent
{
	int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
	[keysDown setObject:[NSNumber numberWithBool:YES] forKey:[NSNumber numberWithInt:key]];
}


- (void) keyUp:(NSEvent *)theEvent
{
	int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
	[keysDown setObject:[NSNumber numberWithBool:NO] forKey:[NSNumber numberWithInt:key]];
}


- (void)reshape
{
	NSRect r = [self convertRectToBase:[self bounds]];
	glViewport(0, 0, r.size.width, r.size.height);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	gluPerspective(60.0, r.size.width/r.size.height, 0.1, 400.0);
	glMatrixMode(GL_MODELVIEW);
}


// Timer callback method
- (void)timerFired:(id)sender
{
	CFAbsoluteTime frameTime = CFAbsoluteTimeGetCurrent();
	float dt = (float)(frameTime - prevFrameTime);
	BOOL wasCameraModified = NO;

	if([[keysDown objectForKey:[NSNumber numberWithInt:'w']] boolValue]) {
        GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0, 0, -cameraSpeed*dt));
        cameraEye = GSVector3_Add(cameraEye, velocity);
        wasCameraModified = YES;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'s']] boolValue]) {
        GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0, 0, cameraSpeed*dt));
        cameraEye = GSVector3_Add(cameraEye, velocity);
        wasCameraModified = YES;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'a']] boolValue]) {
        GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(-cameraSpeed*dt, 0, 0));
        cameraEye = GSVector3_Add(cameraEye, velocity);
        wasCameraModified = YES;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'d']] boolValue]) {
        GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(cameraSpeed*dt, 0, 0));
		cameraEye = GSVector3_Add(cameraEye, velocity);
        wasCameraModified = YES;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'j']] boolValue]) {
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
        wasCameraModified = YES;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'l']] boolValue]) {
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), -cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
        wasCameraModified = YES;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'i']] boolValue]) {
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), -cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
        wasCameraModified = YES;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'k']] boolValue]) {
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), cameraRotSpeed*dt);
        cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
        wasCameraModified = YES;
	}
	
	if(mouseDeltaX != 0) {
		float mouseDirectionX = -mouseDeltaX / mouseSensitivity;
		float angle = mouseDirectionX*dt;
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), angle);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
        wasCameraModified = YES;
	}
	
	if(mouseDeltaY != 0) {
		float mouseDirectionY = -mouseDeltaY / mouseSensitivity;
		float angle = mouseDirectionY*dt;
        GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), angle);
		cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
        wasCameraModified = YES;
	}

    if(wasCameraModified) {
        [self updateCameraLookVectors];
	}

	cubeRotY += cubeRotSpeed * dt;
	
	mouseDeltaX = 0;
	mouseDeltaY = 0;
	prevFrameTime = frameTime;
	[self setNeedsDisplay:YES];
}


- (void)drawRect:(NSRect)dirtyRect
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glPushMatrix();
	
	gluLookAt(cameraEye.x,    cameraEye.y,    cameraEye.z,
              cameraCenter.x, cameraCenter.y, cameraCenter.z,
              cameraUp.x,     cameraUp.y,     cameraUp.z);

	glTranslatef(0, 0, -5);
	glRotatef(cubeRotY, 0, 1, 0);
	[self drawDebugCube];
	
	glPopMatrix();
	glFlush();
}


-(void)dealloc
{
	[keysDown release];
	[super dealloc];
}


// Updated the camera look vectors.
- (void)updateCameraLookVectors
{	
	cameraCenter = GSVector3_Add(cameraEye, GSVector3_Normalize(GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0,0,-1))));	
    cameraUp = GSVector3_Normalize(GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0,1,0)));
}

@end


// Checks for OpenGL errors and logs any that it find. Returns the number of errors.
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
