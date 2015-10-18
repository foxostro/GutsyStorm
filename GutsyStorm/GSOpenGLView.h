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

- (void)setMouseAtCenter;
- (void)enableVSync;
- (void)resetMouseInputSettings;
- (void)timerFired:(id)sender;
- (unsigned)handleUserInput:(float)dt;
- (void)buildFontsAndStrings;
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime;
- (void)shutdown;

@end
