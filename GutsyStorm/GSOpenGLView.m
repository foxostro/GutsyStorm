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
#import <GLKit/GLKMath.h>
#import "GSOpenGLView.h"
#import "GSAppDelegate.h"


static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                      const CVTimeStamp* now,
                                      const CVTimeStamp* outputTime,
                                      CVOptionFlags flagsIn,
                                      CVOptionFlags* flagsOut,
                                      void* displayLinkContext);
int checkGLErrors(void);
BOOL checkForOpenGLExtension(NSString *extension);


@implementation GSOpenGLView
{
    NSTimer *_updateTimer;
    CFAbsoluteTime _prevFrameTime, _lastRenderTime;
    CFAbsoluteTime _lastFpsLabelUpdateTime, _fpsLabelUpdateInterval;
    size_t _numFramesSinceLastFpsLabelUpdate;
    NSMutableDictionary *_keysDown;
    int32_t _mouseDeltaX, _mouseDeltaY;
    float _mouseSensitivity;
    GSCamera *_camera;
    GLString *_fpsStringTex;
    NSMutableDictionary *_stringAttribs; // attributes for string textures
    GSTerrain *_terrain;
    BOOL _spaceBarDebounce;
    BOOL _bKeyDebounce;
    CVDisplayLinkRef _displayLink;
}

// Enables vertical sync for drawing to limit FPS to the screen's refresh rate.
- (void)enableVSync
{
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
}


- (void)buildFontsAndStrings
{
    // init fonts for use with strings
    NSFont* font = [NSFont fontWithName:@"Helvetica" size:12.0];
    _stringAttribs = [[NSMutableDictionary dictionary] retain];
    _stringAttribs[NSFontAttributeName] = font;
    _stringAttribs[NSForegroundColorAttributeName] = [NSColor whiteColor];
    
    _fpsStringTex = [[GLString alloc] initWithString:[NSString stringWithFormat:@"FPS: ?"]
                                      withAttributes:_stringAttribs
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
    
    _terrain = [[GSTerrain alloc] initWithSeed:0
                                       camera:_camera
                                    glContext:[self openGLContext]];
    
    GSAppDelegate *appDelegate = [[NSApplication sharedApplication] delegate];
    appDelegate.terrain = _terrain;
    
    [self enableVSync];
    
    assert(checkGLErrors() == 0);
    
    // Create a display link capable of being used with all active displays
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    
    // Set the renderer output callback function
    CVDisplayLinkSetOutputCallback(_displayLink, &MyDisplayLinkCallback, (void *)self);
    
    // Set the display link for the current renderer
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    
    // Activate the display link
    CVDisplayLinkStart(_displayLink);
}


// Reset mouse input mechanism for camera.
- (void)resetMouseInputSettings
{
    // Reset mouse input mechanism for camera.
    _mouseSensitivity = 500;
    _mouseDeltaX = 0;
    _mouseDeltaY = 0;
    [self setMouseAtCenter];
}


- (void)awakeFromNib
{
    [self  setWantsBestResolutionOpenGLSurface:YES];
    
    _prevFrameTime = _lastRenderTime = _lastFpsLabelUpdateTime = CFAbsoluteTimeGetCurrent();
    _fpsLabelUpdateInterval = 0.3;
    _numFramesSinceLastFpsLabelUpdate = 0;
    _keysDown = [[NSMutableDictionary alloc] init];
    _terrain = nil;
    _spaceBarDebounce = NO;
    _bKeyDebounce = NO;
    
    _camera = [[GSCamera alloc] init];
    [_camera moveToPosition:GLKVector3Make(85.1, 16.1, 140.1)];
    [_camera updateCameraLookVectors];
    [self resetMouseInputSettings];
    
    // Register with window to accept user input.
    [[self window] makeFirstResponder: self];
    [[self window] setAcceptsMouseMovedEvents: YES];
    
    // Register a timer to drive the game loop.
    _updateTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                          target:self
                                        selector:@selector(timerFired:)
                                        userInfo:nil
                                         repeats:YES];
                   
    [[NSRunLoop currentRunLoop] addTimer:_updateTimer 
                                 forMode:NSDefaultRunLoopMode];
}


- (BOOL)acceptsFirstResponder
{
    return YES;
}


- (void)mouseMoved:(NSEvent *)theEvent
{
    static BOOL first = YES;
    
    CGGetLastMouseDelta(&_mouseDeltaX, &_mouseDeltaY);
    
    if(first) {
        first = NO;
        _mouseDeltaX = 0;
        _mouseDeltaY = 0;
    }
    
    [self setMouseAtCenter];
}


// Reset mouse to the center of the view so it can't leave the window.
- (void)setMouseAtCenter
{
    NSRect bounds = [self bounds];
    CGPoint viewCenter;
    viewCenter.x = bounds.origin.x + bounds.size.width / 2;
    viewCenter.y = bounds.origin.y + bounds.size.height / 2;
    CGWarpMouseCursorPosition(viewCenter);
}


- (void)keyDown:(NSEvent *)theEvent
{
    int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
    _keysDown[@(key)] = @YES;
}


- (void)keyUp:(NSEvent *)theEvent
{
    int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
    _keysDown[@(key)] = @NO;
}


- (void)reshape
{
    const float fov = 60.0;
    const float nearD = 0.1;
    const float farD = 724.0;
    
    NSRect r = [self convertRectToBacking:[self bounds]];
    glViewport(0, 0, r.size.width, r.size.height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(fov, r.size.width/r.size.height, nearD, farD);
    glMatrixMode(GL_MODELVIEW);
    
    [_camera reshapeWithBounds:r fov:fov nearD:nearD farD:farD];
    
    assert(checkGLErrors() == 0);
}


// Handle user input and update the camera if it was modified.
- (unsigned)handleUserInput:(float)dt
{
    unsigned cameraModifiedFlags;
    
    cameraModifiedFlags = [_camera handleUserInputForFlyingCameraWithDeltaTime:dt
                                                                   keysDown:_keysDown
                                                                mouseDeltaX:_mouseDeltaX
                                                                mouseDeltaY:_mouseDeltaY
                                                           mouseSensitivity:_mouseSensitivity];
    
    if([_keysDown[@(' ')] boolValue]) {
        if(!_spaceBarDebounce) {
            _spaceBarDebounce = YES;
            [_terrain placeBlockUnderCrosshairs];
        }
    } else {
        _spaceBarDebounce = NO;
    }
    
    if([_keysDown[@('b')] boolValue]) {
        if(!_bKeyDebounce) {
            _bKeyDebounce = YES;
            [_terrain removeBlockUnderCrosshairs];
        }
    } else {
        _bKeyDebounce = NO;
    }
    
    // Reset for the next update
    _mouseDeltaX = 0;
    _mouseDeltaY = 0;
    
    return cameraModifiedFlags;
}


// Timer callback method
- (void)timerFired:(id)sender
{
    CFAbsoluteTime frameTime = CFAbsoluteTimeGetCurrent();
    float dt = (float)(frameTime - _prevFrameTime);
    unsigned cameraModifiedFlags = 0;
    
    // Handle user input and update the camera if it was modified.
    cameraModifiedFlags = [self handleUserInput:dt];
    
    // Allow the chunkStore to update every frame.
    [_terrain updateWithDeltaTime:dt cameraModifiedFlags:cameraModifiedFlags];
    
    _prevFrameTime = frameTime;
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
    glPointSize(5.0);
    glColor4f(0.5f, 0.5f, 0.5f, 1.0f);
    glBegin(GL_POINTS);
    glVertex2f(width/2, height/2);
    glEnd();
    glPointSize(1.0);
    
    // Draw the FPS counter.
    glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
    [_fpsStringTex drawAtPoint:NSMakePoint(10.0f, 10.0f)];
    
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


- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime
{
    static const GLfloat lightDir[] = {0.707, -0.707, -0.707, 0.0};
    
    NSOpenGLContext *currentContext = [self openGLContext];
    [currentContext makeCurrentContext];
    
    // must lock GL context because display link is threaded
    CGLLockContext((CGLContextObj)[currentContext CGLContextObj]);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glPushMatrix();
    glLoadIdentity();
    
    [_camera submitCameraTransform];
    glLightfv(GL_LIGHT0, GL_POSITION, lightDir);

    [_terrain draw];
    
    glPopMatrix(); // camera transform
    
    [self drawHUD];

    [currentContext flushBuffer];
    
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    
    // Update the FPS label every so often.
    if(time - _lastFpsLabelUpdateTime > _fpsLabelUpdateInterval) {
        float fps = _numFramesSinceLastFpsLabelUpdate / (time - _lastFpsLabelUpdateTime);
        _lastFpsLabelUpdateTime = time;
        _numFramesSinceLastFpsLabelUpdate = 0;
        NSString *label = [NSString stringWithFormat:@"FPS: %.1f",fps];
        [_fpsStringTex setString:label withAttributes:_stringAttribs];
    }
    
    _lastRenderTime = time;
    _numFramesSinceLastFpsLabelUpdate++;

    CGLUnlockContext((CGLContextObj)[currentContext CGLContextObj]);
    return kCVReturnSuccess;
}


- (void)dealloc
{
    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
    [_keysDown release];
    [_camera release];
    [_terrain release];
    [super dealloc];
}

@end


// This is the renderer output callback function
static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                      const CVTimeStamp *now,
                                      const CVTimeStamp *outputTime,
                                      CVOptionFlags flagsIn,
                                      CVOptionFlags *flagsOut,
                                      void *displayLinkContext)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CVReturn result;

#if __has_feature(objc_arc)
    result = [(__bridge GSOpenGLView *)displayLinkContext getFrameForTime:outputTime];
#else
    result = [(GSOpenGLView *)displayLinkContext getFrameForTime:outputTime];
#endif

    [pool release];
    return result;
}


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
