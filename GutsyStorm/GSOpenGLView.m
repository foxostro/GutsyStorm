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


static const GLfloat cubeNorms[] = {
	 0, +1,  0,    0, +1,  0,    0, +1,  0, // Top Face
     0, +1,  0,    0, +1,  0,    0, +1,  0,
     0, -1,  0,    0, -1,  0,    0, -1,  0, // Bottom Face
     0, -1,  0,    0, -1,  0,    0, -1,  0,
	 0,  0, +1,    0,  0, +1,    0,  0, +1, // Front Face
	 0,  0, +1,    0,  0, +1,    0,  0, +1,
	 0,  0, -1,    0,  0, -1,    0,  0, -1, // Back Face
	 0,  0, -1,    0,  0, -1,    0,  0, -1,
	+1,  0,  0,   +1,  0,  0,   +1,  0,  0, // Right Face
	+1,  0,  0,   +1,  0,  0,   +1,  0,  0,
	-1,  0,  0,   -1,  0,  0,   -1,  0,  0, // Left Face
	-1,  0,  0,   -1,  0,  0,   -1,  0,  0
};

static const GLsizei numCubeVerts = 12*3;


int checkGLErrors(void);


@implementation GSOpenGLView

// Enables vertical sync for drawing to limit FPS to the screen's refresh rate.
- (void)enableVSync
{
	GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
}


- (NSString *)loadShaderSourceFileWithPath:(NSString *)path
{
    NSError *error;
    NSString *str = [[NSString alloc] initWithContentsOfFile:path
                                                     encoding:NSMacOSRomanStringEncoding
                                                        error:&error];
    if (!str) {
        NSLog(@"Error reading file at %@: %@", path, [error localizedFailureReason]);
        return @"";
    }
    
    return str;
}


- (void)buildShader
{
    if(shader) {
        [shader release];
    }
    
	assert(checkGLErrors() == 0);
    
    NSString *vertFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.vert" ofType:@"txt"];
    NSString *fragFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.frag" ofType:@"txt"];
    
    NSString *vertSrc = [self loadShaderSourceFileWithPath:vertFn];
    NSString *fragSrc = [self loadShaderSourceFileWithPath:fragFn];
        
    shader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    
    [fragSrc release];
    [vertSrc release];
    
	assert(checkGLErrors() == 0);
}


- (void)prepareOpenGL
{
	[[self openGLContext] makeCurrentContext];
	assert(checkGLErrors() == 0);
	
	glClearColor(0.2, 0.4, 0.5, 1.0);
	
	glDisable(GL_LIGHTING);
	glEnable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
    
    // Simple light setup.
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    
    GLfloat lightDir[] = {0.707, -0.707, 0.707, 0.0};
    GLfloat lightAmbient[] = {0.3, 0.3, 0.3, 1.0};
    GLfloat lightDiffuse[] = {0.7, 0.7, 0.7, 1.0};
    GLfloat lightSpecular[] = {1.0, 1.0, 1.0, 1.0};
    
    glLightfv(GL_LIGHT0, GL_POSITION, lightDir);
    glLightfv(GL_LIGHT0, GL_AMBIENT, lightAmbient);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, lightDiffuse);
    glLightfv(GL_LIGHT0, GL_SPECULAR, lightSpecular);
    
    GLfloat materialAmbient[] = {0.3, 0.3, 0.3, 1.0};
    GLfloat materialDiffuse[] = {0.7, 0.7, 0.7, 1.0};
    GLfloat materialSpecular[] = {1.0, 1.0, 1.0, 1.0};
    GLfloat materialShininess = 20.0;
    
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, materialAmbient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, materialDiffuse);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, materialSpecular);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, materialShininess);
	
	// init fonts for use with strings
	NSFont* font = [NSFont fontWithName:@"Helvetica" size:12.0];
	stringAttribs = [[NSMutableDictionary dictionary] retain];
	[stringAttribs setObject:font forKey:NSFontAttributeName];
	[stringAttribs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	[font release];
	
	fpsStringTex = [[GLString alloc] initWithString:[NSString stringWithFormat:@"FPS: ?"]
									  withAttributes:stringAttribs
									   withTextColor:[NSColor whiteColor]
										withBoxColor:[NSColor colorWithDeviceRed:0.3f
																		   green:0.3f
																			blue:0.3f
																		   alpha:1.0f]
									 withBorderColor:[NSColor colorWithDeviceRed:0.7f
																		   green:0.7f
																			blue:0.7f
																		   alpha:1.0f]];
			
	[self generateVBOForDebugCube];
    [self buildShader];
	[self enableVSync];
    
	assert(checkGLErrors() == 0);
}


// Reset mouse input mechanism for camera.
- (void)resetMouseInputSettings
{
	// Reset mouse input mechanism for camera.
	mouseSensitivity = 500;
	mouseDeltaX = 0;
	mouseDeltaY = 0;
	[self setMouseAtCenter];
}


- (void)awakeFromNib
{
	vboCubeVerts = 0;
    vboCubeNorms = 0;
	cubeRotY = 0.0;
	cubeRotSpeed = 10.0;
	prevFrameTime = lastRenderTime = lastFpsLabelUpdateTime = CFAbsoluteTimeGetCurrent();
	fpsLabelUpdateInterval = 0.3;
	numFramesSinceLastFpsLabelUpdate = 0;
	keysDown = [[NSMutableDictionary alloc] init];
    shader = nil;
	
	camera = [[GSCamera alloc] init];
	[self resetMouseInputSettings];
	
	// Register with window to accept user input.
	[[self window] makeFirstResponder: self];
	[[self window] setAcceptsMouseMovedEvents: YES];
	
	// Register a timer to drive the game loop.
	renderTimer = [NSTimer timerWithTimeInterval:0.0167 // 60 FPS
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
    
	glGenBuffers(1, &vboCubeNorms);
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeNorms);
	glBufferData(GL_ARRAY_BUFFER, sizeof(cubeNorms), cubeNorms, GL_STATIC_DRAW);
	
	assert(checkGLErrors() == 0);
}


// Draw a white cube
- (void)drawDebugCube
{	
	glColor4f(1.0, 1.0, 1.0, 1.0);
    
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeVerts);
	glVertexPointer(3, GL_FLOAT, 0, 0);
    
	glBindBuffer(GL_ARRAY_BUFFER, vboCubeNorms);
	glNormalPointer(GL_FLOAT, 0, 0);
    
	glDrawArrays(GL_TRIANGLES, 0, numCubeVerts);
    
	glEnableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_VERTEX_ARRAY);
	 
	assert(checkGLErrors() == 0);
}


- (BOOL)acceptsFirstResponder
{
	return YES;
}


- (void)mouseMoved:(NSEvent *)theEvent
{
	CGGetLastMouseDelta(&mouseDeltaX, &mouseDeltaY);	
	[self setMouseAtCenter];
}


// Reset mouse to the center of the view so it can't leave the window.
- (void)setMouseAtCenter
{
	NSRect bounds = [self bounds];
	CGPoint viewCenter;
	viewCenter.x = bounds.origin.x + bounds.size.width / 2;
	viewCenter.x = bounds.origin.y + bounds.size.height / 2;
	CGWarpMouseCursorPosition(viewCenter);
}


- (void)keyDown:(NSEvent *)theEvent
{
	int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
	[keysDown setObject:[NSNumber numberWithBool:YES] forKey:[NSNumber numberWithInt:key]];
}


- (void)keyUp:(NSEvent *)theEvent
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
	
	assert(checkGLErrors() == 0);
}


// Handle user input and update the camera if it was modified.
- (void)handleUserInput:(float)dt
{
	[camera handleUserInputForFlyingCameraWithDeltaTime:dt
											   keysDown:keysDown
											mouseDeltaX:mouseDeltaX
											mouseDeltaY:mouseDeltaY
									   mouseSensitivity:mouseSensitivity];
	
	// Reset for the next update
	mouseDeltaX = 0;
	mouseDeltaY = 0;
}


// Timer callback method
- (void)timerFired:(id)sender
{
	CFAbsoluteTime frameTime = CFAbsoluteTimeGetCurrent();
	float dt = (float)(frameTime - prevFrameTime);
	
	// Update the FPS label every so often.
	if(frameTime - lastFpsLabelUpdateTime > fpsLabelUpdateInterval) {
		float fps = numFramesSinceLastFpsLabelUpdate / (lastRenderTime - lastFpsLabelUpdateTime);
		lastFpsLabelUpdateTime = frameTime;
		numFramesSinceLastFpsLabelUpdate = 0;
		[fpsStringTex setString:[NSString stringWithFormat:@"FPS: %.1f",fps] withAttributes:stringAttribs];
	}
	
	// Handle user input and update the camera if it was modified.
	[self handleUserInput:dt];

	// The cube spins slowly around the Y-axis.
	cubeRotY += cubeRotSpeed * dt;
	
	prevFrameTime = frameTime;
	[self setNeedsDisplay:YES];
}


// Draws the HUD UI.
- (void)drawHUD
{
	NSRect r = [self bounds];
	GLfloat height = r.size.height;
	GLfloat width = r.size.width;
	
    glDisable(GL_LIGHTING);
	glEnable(GL_TEXTURE_RECTANGLE_EXT);
	glEnable(GL_BLEND);
	glDisable(GL_DEPTH_TEST);
	
	// set orthograhic 1:1 pixel transform in local view coords
	glMatrixMode(GL_PROJECTION);
	glPushMatrix();
	glLoadIdentity();
	glMatrixMode(GL_MODELVIEW);
	glPushMatrix();
	glLoadIdentity();
	glScalef(2.0f / width, -2.0f /  height, 1.0f);
	glTranslatef(-width / 2.0f, -height / 2.0f, 0.0f);
	
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	[fpsStringTex drawAtPoint:NSMakePoint(10.0f, 10.0f)];
	
	// reset orginal martices
	glPopMatrix(); // GL_MODELVIEW
	glMatrixMode(GL_PROJECTION);
	glPopMatrix();
	glMatrixMode(GL_MODELVIEW);
	
    glEnable(GL_LIGHTING);
	glDisable(GL_TEXTURE_RECTANGLE_EXT);
	glDisable(GL_BLEND);
	glEnable(GL_DEPTH_TEST);
}


- (void)drawRect:(NSRect)dirtyRect
{
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
	glPushMatrix();
	[camera submitCameraTransform];
    
    GLfloat lightDir[] = {0.707, -0.707, 0.707, 0.0};    
    glLightfv(GL_LIGHT0, GL_POSITION, lightDir);
    
	glTranslatef(0, 0, -5);
	glRotatef(cubeRotY, 0, 1, 0);
    [shader bind];
	[self drawDebugCube];
    [shader unbind];
	glPopMatrix();
	
	[self drawHUD];

	if ([self inLiveResize]) {
		glFlush();
	} else {
		[[self openGLContext] flushBuffer];
	}
	
	assert(checkGLErrors() == 0);
	
	lastRenderTime = CFAbsoluteTimeGetCurrent();
	numFramesSinceLastFpsLabelUpdate++;
}


- (void)dealloc
{
	[keysDown release];
	[camera release];
	[super dealloc];
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
