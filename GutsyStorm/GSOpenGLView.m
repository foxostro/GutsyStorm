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
#import "GSVector2.h"


int checkGLErrors(void);
BOOL checkForOpenGLExtension(NSString *extension);


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


- (void)buildTerrainShader
{
    [terrainShader release];
    
    assert(checkGLErrors() == 0);
    
    NSString *vertFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.vert" ofType:@"txt"];
    NSString *fragFn = [[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"] pathForResource:@"shader.frag" ofType:@"txt"];
    
    NSString *vertSrc = [self loadShaderSourceFileWithPath:vertFn];
    NSString *fragSrc = [self loadShaderSourceFileWithPath:fragFn];
        
    terrainShader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    
    [fragSrc release];
    [vertSrc release];
    
    [terrainShader bind];
    [terrainShader bindUniformWithNSString:@"tex" val:0]; // texture unit 0
    
    assert(checkGLErrors() == 0);
}


- (void)buildFontsAndStrings
{
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

}


- (void)prepareOpenGL
{
    [[self openGLContext] makeCurrentContext];
    assert(checkGLErrors() == 0);
    
    float glVersion;
    sscanf((char *)glGetString(GL_VERSION), "%f", &glVersion);
    if(glVersion < 2.0) {
        [NSException raise:@"Graphics Card Does Not Meet Requirements"
                    format:@"Graphics card does not support required OpenGL version 2.0"];
    }
    
    if(!checkForOpenGLExtension(@"GL_EXT_texture_array")) {
        [NSException raise:@"Graphics Card Does Not Meet Requirements"
                    format:@"Graphics card does not support required extension: GL_EXT_texture_array"];
    }
    
    glClearColor(0.2, 0.4, 0.5, 1.0);
    
    glDisable(GL_LIGHTING);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    
    glDisable(GL_TEXTURE_2D);
    glActiveTexture(GL_TEXTURE0);
    
    // Simple light setup.
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    
    GLfloat lightDir[] = {0.707, -0.707, -0.707, 0.0};
    GLfloat lightAmbient[] = {0.05, 0.05, 0.05, 1.0};
    GLfloat lightDiffuse[] = {0.6, 0.6, 0.6, 1.0};
    GLfloat lightSpecular[] = {1.0, 1.0, 1.0, 1.0};
    
    glLightfv(GL_LIGHT0, GL_POSITION, lightDir);
    glLightfv(GL_LIGHT0, GL_AMBIENT, lightAmbient);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, lightDiffuse);
    glLightfv(GL_LIGHT0, GL_SPECULAR, lightSpecular);
    
    GLfloat materialAmbient[] = {0.05, 0.05, 0.05, 1.0};
    GLfloat materialDiffuse[] = {0.6, 0.6, 0.6, 1.0};
    GLfloat materialSpecular[] = {1.0, 1.0, 1.0, 1.0};
    GLfloat materialShininess = 5.0;
    
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, materialAmbient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, materialDiffuse);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, materialSpecular);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, materialShininess);
    
    [self buildFontsAndStrings];
    [self buildTerrainShader];
    
    textureArray = [[GSTextureArray alloc] initWithImagePath:[[NSBundle bundleWithIdentifier:@"com.foxostro.GutsyStorm"]
                                                              pathForResource:@"terrain"
                                                              ofType:@"png"]
                                                 numTextures:3];
    
    chunkStore = [[GSChunkStore alloc] initWithSeed:0
                                             camera:camera
                                      terrainShader:terrainShader];
    
    cursor = [[GSCube alloc] init];
    [cursor generateVBO];
        
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
    cubeRotY = 0.0;
    cubeRotSpeed = 10.0;
    prevFrameTime = lastRenderTime = lastFpsLabelUpdateTime = CFAbsoluteTimeGetCurrent();
    fpsLabelUpdateInterval = 0.3;
    numFramesSinceLastFpsLabelUpdate = 0;
    keysDown = [[NSMutableDictionary alloc] init];
    terrainShader = nil;
    textureArray = nil;
    chunkStore = nil;
    spaceBarDebounce = NO;
    bKeyDebounce = NO;
    maxPlaceDistance = 4.0;
    
    // XXX: Should the cursor be handled in its own unique class?
    cursorIsActive = NO;
    cursorPos = GSVector3_Make(0, 0, 0);
    cursor = nil;
    
    camera = [[GSCamera alloc] init];
    [camera moveToPosition:GSVector3_Make(85, 16, 140)];
    [camera updateCameraLookVectors];
    [self resetMouseInputSettings];
    
    // Register with window to accept user input.
    [[self window] makeFirstResponder: self];
    [[self window] setAcceptsMouseMovedEvents: YES];
    
    // Register a timer to drive the game loop.
    renderTimer = [NSTimer timerWithTimeInterval:0.001
                                          target:self
                                        selector:@selector(timerFired:)
                                        userInfo:nil
                                         repeats:YES];
                   
    [[NSRunLoop currentRunLoop] addTimer:renderTimer 
                                 forMode:NSDefaultRunLoopMode];
    
    [[NSRunLoop currentRunLoop] addTimer:renderTimer 
                                 forMode:NSEventTrackingRunLoopMode]; // Ensure timer fires during resize
}


- (BOOL)acceptsFirstResponder
{
    return YES;
}


- (void)mouseMoved:(NSEvent *)theEvent
{
    static BOOL first = YES;
    
    CGGetLastMouseDelta(&mouseDeltaX, &mouseDeltaY);
    
    if(first) {
        first = NO;
        mouseDeltaX = 0;
        mouseDeltaY = 0;
    }
    
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
    const float fov = 60.0;
    const float nearD = 0.1;
    const float farD = 724.0;
    
    NSRect r = [self convertRectToBase:[self bounds]];
    glViewport(0, 0, r.size.width, r.size.height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(fov, r.size.width/r.size.height, nearD, farD);
    glMatrixMode(GL_MODELVIEW);
    
    [camera reshapeWithBounds:r fov:fov nearD:nearD farD:farD];
    
    assert(checkGLErrors() == 0);
}


// Handle user input and update the camera if it was modified.
- (unsigned)handleUserInput:(float)dt
{
    unsigned cameraModifiedFlags;
    
    cameraModifiedFlags = [camera handleUserInputForFlyingCameraWithDeltaTime:dt
                                                                   keysDown:keysDown
                                                                mouseDeltaX:mouseDeltaX
                                                                mouseDeltaY:mouseDeltaY
                                                           mouseSensitivity:mouseSensitivity];
    
    if([[keysDown objectForKey:[NSNumber numberWithInt:' ']] boolValue]) {
        if(!spaceBarDebounce) {
            spaceBarDebounce = YES;
            [self placeBlockUnderCrosshairs];
        }
    } else {
        spaceBarDebounce = NO;
    }
    
    if([[keysDown objectForKey:[NSNumber numberWithInt:'b']] boolValue]) {
        if(!bKeyDebounce) {
            bKeyDebounce = YES;
            [self removeBlockUnderCrosshairs];
        }
    } else {
        bKeyDebounce = NO;
    }
    
    // Reset for the next update
    mouseDeltaX = 0;
    mouseDeltaY = 0;
    
    return cameraModifiedFlags;
}


- (void)placeBlockUnderCrosshairs
{
    GSRay ray = GSRay_Make(camera.cameraEye, GSQuaternion_MulByVec(camera.cameraRot, GSVector3_Make(0, 0, -1)));
    float d;
    
    if([chunkStore getPositionOfBlockAlongRay:ray
                                      maxDist:maxPlaceDistance
                                  outDistance:&d]) {
        // this block is full, so the previous step is where we ought to place the new block
        GSVector3 placePos = GSVector3_Add(ray.origin, GSVector3_Scale(GSVector3_Normalize(ray.direction), MAX(0, d - 0.1f))); // XXX: Messy
        
        voxel_t block;
        block.empty = NO;
        block.outside = NO; // will be recalculated later
        
        [chunkStore placeBlockAtPoint:placePos block:block];
        [self recalcCursorPosition];
    }
}


- (void)removeBlockUnderCrosshairs
{
    GSRay ray = GSRay_Make(camera.cameraEye, GSQuaternion_MulByVec(camera.cameraRot, GSVector3_Make(0, 0, -1)));
    float d;
    
    if([chunkStore getPositionOfBlockAlongRay:ray
                                      maxDist:maxPlaceDistance
                                  outDistance:&d]) {
        GSVector3 removePos = GSVector3_Add(ray.origin, GSVector3_Scale(GSVector3_Normalize(ray.direction), d));
        
        voxel_t block;
        block.empty = YES;
        block.outside = NO; // will be recalculated later
        
        [chunkStore placeBlockAtPoint:removePos block:block];
        [self recalcCursorPosition];
    }
}


- (void)recalcCursorPosition
{
    GSRay ray = GSRay_Make(camera.cameraEye, GSQuaternion_MulByVec(camera.cameraRot, GSVector3_Make(0, 0, -1)));
    float d;
    if([chunkStore getPositionOfBlockAlongRay:ray
                                      maxDist:maxPlaceDistance
                                  outDistance:&d]) {
        cursorPos = GSVector3_Add(ray.origin, GSVector3_Scale(GSVector3_Normalize(ray.direction), d));
        cursorPos = GSVector3_Make((int)cursorPos.x, (int)cursorPos.y, (int)cursorPos.z);
        cursorIsActive = YES;
    } else {
        cursorIsActive = NO;
    }
}


// Timer callback method
- (void)timerFired:(id)sender
{
    CFAbsoluteTime frameTime = CFAbsoluteTimeGetCurrent();
    float dt = (float)(frameTime - prevFrameTime);
    unsigned cameraModifiedFlags = 0;
    
    // Handle user input and update the camera if it was modified.
    cameraModifiedFlags = [self handleUserInput:dt];
    
    //Calculate the cursor position.
    if(cameraModifiedFlags) {
        [self recalcCursorPosition];
    }
    
    // Allow the chunkStore to update every frame.
    [chunkStore updateWithDeltaTime:dt cameraModifiedFlags:cameraModifiedFlags];
    
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
    
    // Draw the crosshairs.
    glLineWidth(4.0);
    glColor4f(0.5f, 0.5f, 0.5f, 1.0f);
    glBegin(GL_LINES);
    glVertex2f(-6 + width/2, -6 + height/2);
    glVertex2f( 6 + width/2,  6 + height/2);
    glVertex2f(-6 + width/2,  6 + height/2);
    glVertex2f( 6 + width/2, -6 + height/2);
    glEnd();
    glLineWidth(1.0);
    
    // Draw the FPS counter.
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
    static const float edgeOffset = 1e-4;
    static const GLfloat lightDir[] = {0.707, -0.707, -0.707, 0.0};
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glPushMatrix();
    glLoadIdentity();
    
    glLoadIdentity();
    [camera submitCameraTransform];
    glLightfv(GL_LIGHT0, GL_POSITION, lightDir);

    glDepthRange(edgeOffset, 1.0); // Use glDepthRange so the block cursor is properly offset from the block itself.
    [chunkStore drawChunks];
    
    if(cursorIsActive) {
        glDepthRange(0.0, 1.0 - edgeOffset);
        glPushMatrix();
        glTranslatef(cursorPos.x, cursorPos.y, cursorPos.z);
        [cursor draw];
        glPopMatrix();
    }
    
    glDepthRange(0.0, 1.0);
    
    glPopMatrix(); // camera transform
    
    [self drawHUD];

    if ([self inLiveResize]) {
        glFlush();
    } else {
        [[self openGLContext] flushBuffer];
    }
    
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    
    // Update the FPS label every so often.
    if(time - lastFpsLabelUpdateTime > fpsLabelUpdateInterval) {
        float fps = numFramesSinceLastFpsLabelUpdate / (time - lastFpsLabelUpdateTime);
        lastFpsLabelUpdateTime = time;
        numFramesSinceLastFpsLabelUpdate = 0;
        NSString *label = [NSString stringWithFormat:@"FPS: %.1f",fps];
        [fpsStringTex setString:label withAttributes:stringAttribs];
    }
    
    lastRenderTime = time;
    numFramesSinceLastFpsLabelUpdate++;
}


- (void)dealloc
{
    [keysDown release];
    [camera release];
    [terrainShader release];
    [textureArray release];
    [cursor release];
    
    [super dealloc];
}

@end


// Returns YES if the given OpenGL extension is supported on this machine.
BOOL checkForOpenGLExtension(NSString *extension)
{
    NSString *extensions = [NSString stringWithCString:(const char *)glGetString(GL_EXTENSIONS)
                                              encoding:NSMacOSRomanStringEncoding];
    NSArray *extensionsArray = [extensions componentsSeparatedByString:@" "];
    
    for(NSString *item in extensionsArray)
    {
        if([item isEqualToString:extension]) {
            return YES;
        }
    }
    
    return NO;
}


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
