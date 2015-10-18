//
//  GSTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSChunkStore.h"
#import "GSCube.h"

@class GSShader;
@class GSCamera;

@interface GSTerrainCursor : NSObject

@property (assign) BOOL cursorIsActive;
@property (assign) vector_float3 cursorPos;
@property (assign) vector_float3 cursorPlacePos;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(NSOpenGLContext *)context shader:(GSShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithCamera:(GSCamera *)camera edgeOffset:(GLfloat)edgeOffset;

@end
