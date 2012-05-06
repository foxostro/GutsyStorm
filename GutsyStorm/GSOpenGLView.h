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
#import "GSTextureArray.h"
#import "GSChunkStore.h"

@interface GSOpenGLView : NSOpenGLView
{
    NSTimer *renderTimer;
    CFAbsoluteTime prevFrameTime, lastRenderTime;
    CFAbsoluteTime lastFpsLabelUpdateTime, fpsLabelUpdateInterval;
    size_t numFramesSinceLastFpsLabelUpdate;
    float cubeRotSpeed;
    float cubeRotY;
    NSMutableDictionary *keysDown;
    int32_t mouseDeltaX, mouseDeltaY;
    float mouseSensitivity;
    GSCamera *camera;
    GLString *fpsStringTex;
    NSMutableDictionary *stringAttribs; // attributes for string textures
    GSShader *terrainShader;
    GSTextureArray *textureArray;
    GSChunkStore *chunkStore;
    BOOL spaceBarDebounce;
}

- (void)drawHUD;
- (void)setMouseAtCenter;
- (void)enableVSync;
- (void)resetMouseInputSettings;
- (void)timerFired:(id)sender;
- (unsigned)handleUserInput:(float)dt;
- (NSString *)loadShaderSourceFileWithPath:(NSString *)path;
- (void)buildTerrainShader;
- (void)buildFontsAndStrings;

@end
