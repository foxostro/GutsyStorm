//
//  GSOpenGLView.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <ApplicationServices/ApplicationServices.h>
#import <CoreVideo/CVDisplayLink.h>
#import <OpenGL/gl.h>
#import "GSOpenGLView.h"
#import "GSVBOHolder.h"
#import "GSShader.h"
#import "GSMatrixUtils.h"
#import "GSOpenGLViewController.h"
#import "GSTextLabel.h"


static CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                      const CVTimeStamp* now,
                                      const CVTimeStamp* outputTime,
                                      CVOptionFlags flagsIn,
                                      CVOptionFlags* flagsOut,
                                      void* displayLinkContext);
BOOL checkForOpenGLExtension(NSString *extension);
NSString * _Nonnull stringForOpenGLError(GLenum error);
int checkGLErrors(void);


@interface GSOpenGLView ()

- (void)enableVSync;
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime;

@end


@implementation GSOpenGLView
{
    CVDisplayLinkRef _displayLink;
    GSVBOHolder *_vboCrosshairs;
    GSShader *_shaderCrosshairs;

    BOOL _displayLinkShouldShutdown;
    dispatch_semaphore_t _semaDisplayLinkShutdown;
}

+ (nonnull GSShader *)newCrosshairShader
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *vertFn = [bundle pathForResource:@"crosshairs.vert" ofType:@"txt"];
    NSString *fragFn = [bundle pathForResource:@"crosshairs.frag" ofType:@"txt"];
    NSString *vertSrc = [[NSString alloc] initWithContentsOfFile:vertFn
                                                        encoding:NSMacOSRomanStringEncoding
                                                           error:nil];
    NSString *fragSrc = [[NSString alloc] initWithContentsOfFile:fragFn
                                                        encoding:NSMacOSRomanStringEncoding
                                                           error:nil];
    GSShader *shader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    return shader;
}

+ (nonnull GSVBOHolder *)newCrosshairsVboWithContext:(NSOpenGLContext *)context
{
    vector_float4 crosshair_vertex = {400, 300, 0, 1};
    GLuint handle = 0;
    glGenBuffers(1, &handle);
    glBindBuffer(GL_ARRAY_BUFFER, handle);
    glBufferData(GL_ARRAY_BUFFER, sizeof(crosshair_vertex), &crosshair_vertex, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    return [[GSVBOHolder alloc] initWithHandle:handle context:context];
}

// Enables vertical sync for drawing to limit FPS to the screen's refresh rate.
- (void)enableVSync
{
    GLint swapInt = 1;
    [[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
}

- (void)prepareOpenGL
{
    CVReturn ret;

    [self.openGLContext makeCurrentContext];
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
    
    _vboCrosshairs = [[self class] newCrosshairsVboWithContext:self.openGLContext];
    _shaderCrosshairs = [[self class] newCrosshairShader];

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
    ret = CVDisplayLinkStart(_displayLink);
    if (ret != kCVReturnSuccess) {
        NSString *s = [NSString stringWithFormat:@"Display link error and no real way to handle it here: %d", (int)ret];
        @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
    }
}

- (void)awakeFromNib
{
    [self setWantsBestResolutionOpenGLSurface:YES];

    _displayLinkShouldShutdown = NO;
    _semaDisplayLinkShutdown = dispatch_semaphore_create(0);
}

- (void)reshape
{
    NSRect r = [self convertRectToBacking:self.bounds];
    CGSize size = r.size;
    glViewport(0, 0, size.width, size.height);
    [self.delegate openGLView:self drawableSizeWillChange:size];
}

- (void)drawHUD
{
    NSRect bounds = self.bounds;
    GLfloat height = bounds.size.height;
    GLfloat width = bounds.size.width;
    matrix_float4x4 scale = GSMatrixFromScale((vector_float4){2.0f / width, -2.0f /  height, 1.0f, 1.0f});
    matrix_float4x4 translation = GSMatrixFromTranslation((vector_float3){-width / 2.0f, -height / 2.0f, 0.0f});
    matrix_float4x4 mvp = matrix_multiply(translation, scale);

    vector_float4 crosshairPosition = {width / 2.0f, height / 2.0f, 0.0, 1.0};
    
    // Draw the cross hairs.
    glEnable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glPointSize(5.0);
    [_shaderCrosshairs bind];
    [_shaderCrosshairs bindUniformWithMatrix4x4:mvp name:@"mvp"];
    glBindBuffer(GL_ARRAY_BUFFER, _vboCrosshairs.handle);
    glBufferData(GL_ARRAY_BUFFER, sizeof(crosshairPosition), &crosshairPosition, GL_DYNAMIC_DRAW);
    glVertexPointer(4, GL_FLOAT, 0, 0);
    glEnableClientState(GL_VERTEX_ARRAY);
    glDrawArrays(GL_POINTS, 0, 1);
    glDisableClientState(GL_VERTEX_ARRAY);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    [_shaderCrosshairs unbind];
    glPointSize(1.0);
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);

    assert(checkGLErrors() == 0);
}

- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime
{
    if (_displayLinkShouldShutdown) {
        dispatch_semaphore_signal(_semaDisplayLinkShutdown);
        return kCVReturnSuccess;
    }

    NSOpenGLContext *currentContext = [self openGLContext];
    [currentContext makeCurrentContext];

    // must lock GL context because display link is threaded
    CGLLockContext((CGLContextObj)[currentContext CGLContextObj]);

    assert(checkGLErrors() == 0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    [self.delegate drawInOpenGLView:self];
    [self drawHUD];
    [currentContext flushBuffer];

    CGLUnlockContext((CGLContextObj)[currentContext CGLContextObj]);
    return kCVReturnSuccess;
}

- (void)dealloc
{
    CVDisplayLinkRelease(_displayLink);
}

- (void)shutdown
{
    _displayLinkShouldShutdown = YES;

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
    NSArray<NSString *> *extensionsArray = [extensions componentsSeparatedByString:@" "];

    for(NSString *item in extensionsArray)
    {
        if([item isEqualToString:extension]) {
            return YES;
        }
    }

    return NO;
}

NSString * _Nonnull stringForOpenGLError(GLenum error)
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
