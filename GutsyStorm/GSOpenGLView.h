//
//  GutsyStormOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface GSOpenGLView : NSOpenGLView
{
	GLuint vboCubeVerts;
	NSTimer* renderTimer;
	CFAbsoluteTime prevFrameTime;
	float cubeRotSpeed;
	float cubeRotY;
	NSMutableDictionary* keysDown;
}

- (void)drawDebugCube;

- (void)timerFired:(id)sender;

@end
