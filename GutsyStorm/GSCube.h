//
//  GSCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <simd/matrix.h>

@class NSOpenGLContext;
@class FoxShader;

@interface GSCube : NSObject

- (nullable instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithContext:(nonnull NSOpenGLContext *)context
                                  shader:(nonnull FoxShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithModelViewProjectionMatrix:(matrix_float4x4)mvp;

@end
