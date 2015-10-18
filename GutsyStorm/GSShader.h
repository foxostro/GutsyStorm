//
//  GSShader.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/20/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <simd/matrix.h>

@interface GSShader : NSObject

- (instancetype)initWithVertexShaderSource:(NSString *)vert
                      fragmentShaderSource:(NSString *)frag;
- (void)bind;
- (void)unbind;
- (void)bindUniformWithInt:(GLint)value name:(NSString *)name;
- (void)bindUniformWithMatrix4x4:(matrix_float4x4)value name:(NSString *)name;
- (void)bindUniformWithVector2:(vector_float2)value name:(NSString *)name;

@end
