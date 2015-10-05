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
BOOL checkForOpenGLExtension(NSString *extension);
NSString *stringForOpenGLError(GLenum error);
int checkGLErrors(void);


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
    __weak GSTerrain *_terrain;
    BOOL _spaceBarDebounce;
    BOOL _bKeyDebounce;
    BOOL _uKeyDebounce;
    CVDisplayLinkRef _displayLink;

    BOOL _timerShouldShutdown;
    dispatch_semaphore_t _semaTimerShutdown;

    BOOL _displayLinkShouldShutdown;
    dispatch_semaphore_t _semaDisplayLinkShutdown;
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
    _stringAttribs = [NSMutableDictionary dictionary];
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
    CVReturn ret;

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

    GSTerrain *terrain = [[GSTerrain alloc] initWithSeed:0
                                                  camera:_camera
                                               glContext:[self openGLContext]];
    
    GSAppDelegate *appDelegate = [[NSApplication sharedApplication] delegate];
    appDelegate.terrain = terrain;
    _terrain = terrain;
    
    [self enableVSync];
    
    assert(checkGLErrors() == 0);
    
    // Create a display link capable of being used with all active displays
    ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
    
    // Set the renderer output callback function
    ret = CVDisplayLinkSetOutputCallback(_displayLink, &MyDisplayLinkCallback, (__bridge void *)self);
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
    
    // Set the display link for the current renderer
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    ret = CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
    
    // Activate the display link
    appDelegate.openGlView = self;
    ret = CVDisplayLinkStart(_displayLink);
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
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
    _uKeyDebounce = NO;

    _timerShouldShutdown = NO;
    _semaTimerShutdown = dispatch_semaphore_create(0);

    _displayLinkShouldShutdown = NO;
    _semaDisplayLinkShutdown = dispatch_semaphore_create(0);

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
    const float fovRadians = 60.0 * (M_PI / 180.0);
    const float nearD = 0.1;
    const float farD = 724.0;
    
    NSRect r = [self convertRectToBacking:[self bounds]];
    glViewport(0, 0, r.size.width, r.size.height);
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(GLKMatrix4MakePerspective(fovRadians, r.size.width/r.size.height, nearD, farD).m);
    glMatrixMode(GL_MODELVIEW);
    
    [_camera reshapeWithBounds:r fov:fovRadians nearD:nearD farD:farD];
    
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

    if([_keysDown[@('u')] boolValue]) {
        if(!_uKeyDebounce) {
            _uKeyDebounce = YES;
            [_terrain testPurge];
        }
    } else {
        _uKeyDebounce = NO;
    }

    // Reset for the next update
    _mouseDeltaX = 0;
    _mouseDeltaY = 0;

    return cameraModifiedFlags;
}

// Timer callback method
- (void)timerFired:(id)sender
{
    if (_timerShouldShutdown) {
        dispatch_semaphore_signal(_semaTimerShutdown);
        return;
    }

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
    if (_displayLinkShouldShutdown) {
        dispatch_semaphore_signal(_semaDisplayLinkShutdown);
        return kCVReturnSuccess;
    }

    static const GLfloat lightDir[] = {0.707, -0.707, -0.707, 0.0};

    NSOpenGLContext *currentContext = [self openGLContext];
    [currentContext makeCurrentContext];

    // must lock GL context because display link is threaded
    CGLLockContext((CGLContextObj)[currentContext CGLContextObj]);

    // FIXME: Frequently, the call to glClear will fail with "invalid framebuffer operation" when the application is quitting.
    assert(checkGLErrors() == 0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    if(checkGLErrors() > 0) {
        NSLog(@"ignoring OpenGL error");
        CGLUnlockContext((CGLContextObj)[currentContext CGLContextObj]);
        return kCVReturnError;
    }

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
    CVDisplayLinkRelease(_displayLink);
}

- (void)shutdown
{
    _timerShouldShutdown = YES;
    _displayLinkShouldShutdown = YES;

    dispatch_semaphore_wait(_semaTimerShutdown, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/30.0));
    [_updateTimer invalidate];

    // Calling CVDisplayLinkStop will kill the display link thread. So, cleanly shutdown first.
    dispatch_semaphore_wait(_semaDisplayLinkShutdown, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/60.0));
    CVReturn ret = CVDisplayLinkStop(_displayLink);
    
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
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
    @autoreleasepool {
        return [(__bridge GSOpenGLView *)displayLinkContext getFrameForTime:outputTime];
    }
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

NSString *stringForOpenGLError(GLenum error)
{
    switch(error)
    {
    case GL_NO_ERROR:
        return @"No error has been recorded.";

    case GL_INVALID_ENUM:
        return @"An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag.";

    case GL_INVALID_VALUE:
        return @"A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag.";

    case GL_INVALID_OPERATION:
        return @"The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag.";

    case GL_INVALID_FRAMEBUFFER_OPERATION:
        return @"The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag.";

    case GL_OUT_OF_MEMORY:
        return @"There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded.";

    case GL_STACK_UNDERFLOW:
        return @"An attempt has been made to perform an operation that would cause an internal stack to underflow.";

    case GL_STACK_OVERFLOW:
        return @"An attempt has been made to perform an operation that would cause an internal stack to overflow.";

    default:
        return @"Unknown OpenGL error";
    }
}

// Checks for OpenGL errors and logs any that it find. Returns the number of errors.
int checkGLErrors(void)
{
    int errCount = 0;

    for(GLenum currError = glGetError(); currError != GL_NO_ERROR; currError = glGetError())
    {
        NSLog(@"OpenGL Error: %@", stringForOpenGLError(currError));
        ++errCount;
    }

    return errCount;
}
