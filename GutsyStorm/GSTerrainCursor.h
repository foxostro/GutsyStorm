//
//  GSTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
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

- (nullable instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithContext:(nonnull NSOpenGLContext *)context
                                  shader:(nonnull GSShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithCamera:(nonnull GSCamera *)camera;

@end
