//
//  GSCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <simd/matrix.h>

@class NSOpenGLContext;
@class GSShader;

@interface GSCube : NSObject

- (nullable instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithContext:(nonnull NSOpenGLContext *)context
                                  shader:(nonnull GSShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)drawWithModelViewProjectionMatrix:(matrix_float4x4)mvp;

@end
