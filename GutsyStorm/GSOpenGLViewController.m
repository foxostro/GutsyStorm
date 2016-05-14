//
//  GSOpenGLViewController.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015-2016 Andrew Fox. All rights reserved.
//

#import "GSOpenGLViewController.h"
#import "GSTextLabel.h"
#import "GSTerrain.h"
#import "GSTerrainJournal.h"
#import "GSCamera.h"
#import "GSOpenGLView.h"
#import "GSMatrixUtils.h"
#import "GSTerrainModifyBlockBenchmark.h"


@interface GSOpenGLViewController ()

// Reset mouse input mechanism for camera.
- (void)resetMouseInputSettings;

// Reset mouse to the center of the view so it can't leave the window.
- (void)setMouseAtCenter;

// Process user input on a timer.
- (unsigned)handleUserInput:(float)dt;

@end


@implementation GSOpenGLViewController
{
    GSTextLabel *_frameRateLabel;
    GSTerrain *_terrain;
    GSCamera *_camera;
    GSOpenGLView *_openGlView;
    dispatch_source_t _memoryPressureSource;

    float _mouseSensitivity;
    int32_t _mouseDeltaX, _mouseDeltaY;

    BOOL _spaceBarDebounce;
    BOOL _vKeyDebounce;
    BOOL _cKeyDebounce;
    BOOL _bKeyDebounce;
    BOOL _uKeyDebounce;
    BOOL _pKeyDebounce;
    BOOL _yKeyDebounce;
    NSMutableDictionary<NSNumber *, NSNumber *> *_keysDown;

    NSTimer *_updateTimer;
    BOOL _timerShouldShutdown;
    dispatch_semaphore_t _semaTimerShutdown;

    CFAbsoluteTime _prevFrameTime, _lastRenderTime;
    CFAbsoluteTime _lastFpsLabelUpdateTime, _fpsLabelUpdateInterval;
    size_t _numFramesSinceLastFpsLabelUpdate;
}

+ (void)initialize
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"]]];
}

+ (nonnull NSURL *)newTerrainJournalURL
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *path = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    
    path = [path stringByAppendingPathComponent:bundleIdentifier];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    path = [path stringByAppendingPathComponent:@"terrain-journal.plist"];

    NSURL *url = [[NSURL alloc] initFileURLWithPath:path isDirectory:NO];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSLog(@"Terrain journal file is not accessible at %@", url);
    }
    
    return url;
}

- (void)applicationWillTerminate:(nonnull NSNotification *)notification
{
    if (_memoryPressureSource) {
        dispatch_source_cancel(_memoryPressureSource);
        _memoryPressureSource = nil;
    }
    _timerShouldShutdown = YES;
    if (_semaTimerShutdown) {
        dispatch_semaphore_wait(_semaTimerShutdown, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/30.0));
        _semaTimerShutdown = nil;
    }
    [_updateTimer invalidate];

    [_openGlView shutdown];
    [_terrain shutdown];

    _updateTimer = nil;
    _terrain = nil;
    _openGlView = nil;
}

- (GSTerrainJournal *)fetchJournal
{
    NSURL *journalUrl = [[self class] newTerrainJournalURL];
    NSLog(@"Terrain edit journal stored at %@", journalUrl);
    GSTerrainJournal *journal = [NSKeyedUnarchiver unarchiveObjectWithFile:[journalUrl path]];

    if (!journal) {
        NSLog(@"Creating new journal.");
        journal = [[GSTerrainJournal alloc] init];
    }

    journal.url = journalUrl;

    return journal;
}

- (void)benchmark
{
    GSTerrainModifyBlockBenchmark *benchmark;
    benchmark = [[GSTerrainModifyBlockBenchmark alloc] initWithOpenGLContext:_openGlView.openGLContext];
    [benchmark run];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (NSClassFromString(@"XCTestCase")) {
        return;
    }

    _openGlView = (GSOpenGLView *)self.view;
    _openGlView.delegate = self;
    [_openGlView.window makeFirstResponder: self];
    [_openGlView.window setAcceptsMouseMovedEvents: YES];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Benchmark"]) {
        [self benchmark];
        [NSApp terminate:nil];
    }

    _spaceBarDebounce = NO;
    _bKeyDebounce = NO;
    _uKeyDebounce = NO;
    _pKeyDebounce = NO;
    _keysDown = [NSMutableDictionary<NSNumber *, NSNumber *> new];
    
    _camera = [GSCamera new];
    [_camera moveToPosition:(vector_float3){85.1, 16.1, 140.1}];
    [_camera updateCameraLookVectors];

    [self resetMouseInputSettings];
    
    _frameRateLabel = [GSTextLabel new];

    _terrain = [[GSTerrain alloc] initWithJournal:[self fetchJournal]
                                           camera:_camera
                                        glContext:_openGlView.openGLContext];

    _prevFrameTime = _lastRenderTime = _lastFpsLabelUpdateTime = CFAbsoluteTimeGetCurrent();
    _fpsLabelUpdateInterval = 0.3;
    _numFramesSinceLastFpsLabelUpdate = 0;

    _timerShouldShutdown = NO;
    _semaTimerShutdown = dispatch_semaphore_create(0);
    
    // Listen for memory pressure notifications and forward them to the terrain object.
    _memoryPressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
                                                   DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN |
                                                   DISPATCH_MEMORYPRESSURE_CRITICAL, dispatch_get_main_queue());
    dispatch_source_set_event_handler(_memoryPressureSource, ^{
        dispatch_source_memorypressure_flags_t status = dispatch_source_get_data(_memoryPressureSource);
        [_terrain memoryPressure:status];
    });
    dispatch_resume(_memoryPressureSource);
    
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

- (void)mouseMoved:(nonnull NSEvent *)theEvent
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

- (void)keyDown:(nonnull NSEvent *)theEvent
{
    int key = [[theEvent charactersIgnoringModifiers] characterAtIndex:0];
    _keysDown[@(key)] = @YES;
}

- (void)keyUp:(nonnull NSEvent *)theEvent
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
    
    if([_keysDown[@('c')] boolValue]) {
        if(!_cKeyDebounce) {
            _cKeyDebounce = YES;
            [_terrain removeTorchUnderCrosshairs];
        }
    } else {
        _cKeyDebounce = NO;
    }
    
    if([_keysDown[@('v')] boolValue]) {
        if(!_vKeyDebounce) {
            _vKeyDebounce = YES;
            [_terrain placeTorchUnderCrosshairs];
        }
    } else {
        _vKeyDebounce = NO;
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
            [_terrain memoryPressure:DISPATCH_MEMORYPRESSURE_CRITICAL];
        }
    } else {
        _uKeyDebounce = NO;
    }
    
    if([_keysDown[@('y')] boolValue]) {
        if(!_yKeyDebounce) {
            _yKeyDebounce = YES;
            [_terrain memoryPressure:DISPATCH_MEMORYPRESSURE_WARN];
        }
    } else {
        _yKeyDebounce = NO;
    }
    
    if([_keysDown[@('p')] boolValue]) {
        if(!_pKeyDebounce) {
            _pKeyDebounce = YES;
            [_terrain printInfo];
        }
    } else {
        _pKeyDebounce = NO;
    }
    
    // Reset for the next update
    _mouseDeltaX = 0;
    _mouseDeltaY = 0;
    
    return cameraModifiedFlags;
}

- (void)timerFired:(nonnull id)sender
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

- (void)openGLView:(nonnull GSOpenGLView *)view drawableSizeWillChange:(CGSize)size
{
    const float fovyRadians = 60.0 * (M_PI / 180.0);
    const float nearZ = 0.1;
    const float farZ = 2048.0;
    [_camera reshapeWithSize:size fov:fovyRadians nearD:nearZ farD:farZ];

    GLfloat height = size.height;
    GLfloat width = size.width;
    matrix_float4x4 scale = GSMatrixFromScale((vector_float4){2.0f / width, -2.0f /  size.height, 1.0f, 1.0f});
    matrix_float4x4 translation = GSMatrixFromTranslation((vector_float3){-width / 2.0f, -height / 2.0f, 0.0f});
    matrix_float4x4 projection = matrix_multiply(translation, scale);
    _frameRateLabel.projectionMatrix = projection;
}

- (void)drawInOpenGLView:(nonnull GSOpenGLView *)view
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