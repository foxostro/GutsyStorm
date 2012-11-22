//
//  GSOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreVideo/CVDisplayLink.h>
#import "GSCamera.h"
#import "GLString.h"
#import "GSTerrain.h"

@interface GSOpenGLView : NSOpenGLView
{
    NSTimer *updateTimer;
    CFAbsoluteTime prevFrameTime, lastRenderTime;
    CFAbsoluteTime lastFpsLabelUpdateTime, fpsLabelUpdateInterval;
    size_t numFramesSinceLastFpsLabelUpdate;
    NSMutableDictionary *keysDown;
    int32_t mouseDeltaX, mouseDeltaY;
    float mouseSensitivity;
    GSCamera *camera;
    GLString *fpsStringTex;
    NSMutableDictionary *stringAttribs; // attributes for string textures
    GSTerrain *terrain;
    BOOL spaceBarDebounce;
    BOOL bKeyDebounce;
    CVDisplayLinkRef displayLink;
}

- (void)drawHUD;
- (void)setMouseAtCenter;
- (void)enableVSync;
- (void)resetMouseInputSettings;
- (void)timerFired:(id)sender;
- (unsigned)handleUserInput:(float)dt;
- (void)buildFontsAndStrings;
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime;

@end
