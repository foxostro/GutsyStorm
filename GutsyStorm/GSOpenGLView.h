//
//  GSOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSCamera.h"
#import "GLString.h"
#import "GSShader.h"

@interface GSOpenGLView : NSOpenGLView
{
	GLuint vboCubeVerts, vboCubeNorms;
	NSTimer* renderTimer;
	CFAbsoluteTime prevFrameTime, lastRenderTime;
	CFAbsoluteTime lastFpsLabelUpdateTime, fpsLabelUpdateInterval;
	size_t numFramesSinceLastFpsLabelUpdate;
	float cubeRotSpeed;
	float cubeRotY;
	NSMutableDictionary* keysDown;
	int32_t mouseDeltaX, mouseDeltaY;
	float mouseSensitivity;
	GSCamera* camera;
	GLString * fpsStringTex;
	NSMutableDictionary * stringAttribs; // attributes for string textures
    GSShader *shader;
}

- (void)drawHUD;
- (void)drawDebugCube;
- (void)setMouseAtCenter;
- (void)generateVBOForDebugCube;
- (void)enableVSync;
- (void)resetMouseInputSettings;
- (void)timerFired:(id)sender;
- (void)handleUserInput:(float)dt;
- (NSString *)loadShaderSourceFileWithPath:(NSString *)path;
- (void)buildShader;

@end
