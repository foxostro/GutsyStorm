//
//  GSShader.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/20/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

@interface GSShader : NSObject

- (id)initWithVertexShaderSource:(NSString *)vert
            fragmentShaderSource:(NSString *)frag;
- (void)bind;
- (void)unbind;
- (void)bindUniformWithNSString:(NSString *)name val:(GLint)val;

@end
