//
//  GSOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSVector3.h"
#import "GSQuaternion.h"

@interface GSOpenGLView : NSOpenGLView
{
	GLuint vboCubeVerts;
	NSTimer* renderTimer;
	CFAbsoluteTime prevFrameTime;
	float cubeRotSpeed;
	float cubeRotY;
	NSMutableDictionary* keysDown;
	int32_t mouseDeltaX, mouseDeltaY;
	float mouseSensitivity;
	float cameraSpeed, cameraRotSpeed;
	GSQuaternion cameraRot;
	GSVector3 cameraEye, cameraCenter, cameraUp;
}

- (void)drawDebugCube;
- (void)timerFired:(id)sender;
- (void)updateCameraLookVectors;
- (void)setMouseAtCenter;
- (void)generateVBOForDebugCube;
- (void)enableVSync;
- (void)setupDefaultCamera;

@end
