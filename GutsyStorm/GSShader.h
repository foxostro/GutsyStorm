//
//  GSShader.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/20/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <simd/matrix.h>

@interface GSShader : NSObject

- (nullable instancetype)initWithVertexShaderSource:(nonnull NSString *)vert
                               fragmentShaderSource:(nonnull NSString *)frag;
- (void)bind;
- (void)unbind;
- (void)bindUniformWithInt:(int)value name:(nonnull NSString *)name;
- (void)bindUniformWithMatrix4x4:(matrix_float4x4)value name:(nonnull NSString *)name;
- (void)bindUniformWithVector2:(vector_float2)value name:(nonnull NSString *)name;

@end
