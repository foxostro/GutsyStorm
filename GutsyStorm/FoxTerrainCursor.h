//
//  FoxTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxChunkStore.h"
#import "FoxCube.h"

@class FoxShader;
@class FoxCamera;

@interface FoxTerrainCursor : NSObject

@property (assign) BOOL cursorIsActive;
@property (assign) vector_float3 cursorPos;
@property (assign) vector_float3 cursorPlacePos;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(NSOpenGLContext *)context shader:(FoxShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithCamera:(FoxCamera *)camera edgeOffset:(GLfloat)edgeOffset;

@end
