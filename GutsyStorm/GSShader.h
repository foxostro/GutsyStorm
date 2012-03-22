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
{
    GLuint handle;
    BOOL linked;
}

- (id)initWithVertexShaderSource:(NSString *)vert
            fragmentShaderSource:(NSString *)frag;

- (const GLchar **)buildSourceStringsArray:(NSString *)source
                                    length:(GLsizei *)length;

- (NSString *)getShaderInfoLog:(GLuint)shader;

- (NSString *)getProgramInfoLog:(GLuint)program;

- (BOOL)wasShaderCompileSuccessful:(GLuint)shader;

- (BOOL)wasProgramLinkSuccessful:(GLuint)shader;

- (void)createShaderWithSource:(NSString *)sourceString
                          type:(GLenum)type;

- (void)link;

- (void)bind;

- (void)unbind;

- (void)bindUniformWithNSString:(NSString *)name val:(GLint)val;

@end
