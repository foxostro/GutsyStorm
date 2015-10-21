//
//  FoxCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <simd/matrix.h>

@class NSOpenGLContext;
@class FoxShader;

@interface FoxCube : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(NSOpenGLContext *)context
                         shader:(FoxShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithModelViewProjectionMatrix:(matrix_float4x4)mvp;

@end
