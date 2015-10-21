//
//  FoxOpenGLViewController.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import "FoxOpenGLViewController.h"
#import "FoxTextLabel.h"
#import "FoxTerrain.h"
#import "FoxCamera.h"
#import "FoxOpenGLView.h"
#import "FoxMatrixUtils.h"


@interface FoxOpenGLViewController ()

// Reset mouse input mechanism for camera.
- (void)resetMouseInputSettings;

// Reset mouse to the center of the view so it can't leave the window.
- (void)setMouseAtCenter;

// Process user input on a timer.
- (unsigned)handleUserInput:(float)dt;

@end


@implementation FoxOpenGLViewController
{
    FoxTextLabel *_frameRateLabel;
    FoxTerrain *_terrain;
    FoxCamera *_camera;
    FoxOpenGLView *_openGlView;

    float _mouseSensitivity;
    int32_t _mouseDeltaX, _mouseDeltaY;

    BOOL _spaceBarDebounce;
    BOOL _bKeyDebounce;
    BOOL _uKeyDebounce;
    NSMutableDictionary<NSNumber *, NSNumber *> *_keysDown;
    
    NSTimer *_updateTimer;
    BOOL _timerShouldShutdown;
    dispatch_semaphore_t _semaTimerShutdown;

    CFAbsoluteTime _prevFrameTime, _lastRenderTime;
    CFAbsoluteTime _lastFpsLabelUpdateTime, _fpsLabelUpdateInterval;
    size_t _numFramesSinceLastFpsLabelUpdate;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    _timerShouldShutdown = YES;
    dispatch_semaphore_wait(_semaTimerShutdown, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/30.0));
    [_updateTimer invalidate];

    [_openGlView shutdown];
    [_terrain shutdown];

    _updateTimer = nil;
    _terrain = nil;
    _openGlView = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do view setup here.

    _openGlView = (FoxOpenGLView *)self.view;
    _openGlView.delegate = self;
    [_openGlView.window makeFirstResponder: self];
    [_openGlView.window setAcceptsMouseMovedEvents: YES];

    _spaceBarDebounce = NO;
    _bKeyDebounce = NO;
    _uKeyDebounce = NO;
    _keysDown = [NSMutableDictionary<NSNumber *, NSNumber *> new];
    
    _camera = [FoxCamera new];
    [_camera moveToPosition:(vector_float3){85.1, 16.1, 140.1}];
    [_camera updateCameraLookVectors];

    [self resetMouseInputSettings];
    
    _frameRateLabel = [FoxTextLabel new];
    
    _terrain = [[FoxTerrain alloc] initWithSeed:0 camera:_camera glContext:_openGlView.openGLContext];

    _prevFrameTime = _lastRenderTime = _lastFpsLabelUpdateTime = CFAbsoluteTimeGetCurrent();
    _fpsLabelUpdateInterval = 0.3;
    _numFramesSinceLastFpsLabelUpdate = 0;

    _timerShouldShutdown = NO;
    _semaTimerShutdown = dispatch_semaphore_create(0);
    
    // Register a timer to drive the game loop.
    _updateTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0
                                           target:self
                                         selector:@selector(timerFired:)
                                         userInfo:nil
                                          repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSDefaultRunLoopMode];
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

- (void)resetMouseInputSettings
{
    // Reset mouse input mechanism for camera.
    _mouseSensitivity = 500;
    _mouseDeltaX = 0;
    _mouseDeltaY = 0;
    [self setMouseAtCenter];
}

- (void)setMouseAtCenter
{
    NSRect bounds = self.view.bounds;
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

- (void)openGLView:(FoxOpenGLView *)view drawableSizeWillChange:(CGSize)size
{
    const float fovyRadians = 60.0 * (M_PI / 180.0);
    const float nearZ = 0.1;
    const float farZ = 2048.0;
    [_camera reshapeWithSize:size fov:fovyRadians nearD:nearZ farD:farZ];

    GLfloat height = size.height;
    GLfloat width = size.width;
    matrix_float4x4 scale = matrix_from_scale((vector_float4){2.0f / width, -2.0f /  size.height, 1.0f, 1.0f});
    matrix_float4x4 translation = matrix_from_translation((vector_float3){-width / 2.0f, -height / 2.0f, 0.0f});
    matrix_float4x4 projection = matrix_multiply(translation, scale);
    _frameRateLabel.projectionMatrix = projection;
}

- (void)drawInOpenGLView:(FoxOpenGLView *)view
{
    [_terrain draw];
    [_frameRateLabel drawAtPoint:NSMakePoint(10.0f, 10.0f)];

    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    
    // Update the FPS label every so often.
    if(time - _lastFpsLabelUpdateTime > _fpsLabelUpdateInterval) {
        float fps = _numFramesSinceLastFpsLabelUpdate / (time - _lastFpsLabelUpdateTime);
        _lastFpsLabelUpdateTime = time;
        _numFramesSinceLastFpsLabelUpdate = 0;
        _frameRateLabel.text = [NSString stringWithFormat:@"FPS: %.1f", fps];
    }
    
    _lastRenderTime = time;
    _numFramesSinceLastFpsLabelUpdate++;
}

@end