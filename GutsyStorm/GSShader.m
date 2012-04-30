//
//  GSShader.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/20/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import "GSShader.h"


extern int checkGLErrors(void);


@interface GSShader (Private)

- (const GLchar **)buildSourceStringsArray:(NSString *)source
                                    length:(GLsizei *)length;

- (NSString *)getShaderInfoLog:(GLuint)shader;
- (NSString *)getProgramInfoLog:(GLuint)program;
- (BOOL)wasShaderCompileSuccessful:(GLuint)shader;
- (BOOL)wasProgramLinkSuccessful:(GLuint)shader;
- (void)createShaderWithSource:(NSString *)sourceString
                          type:(GLenum)type;
- (void)link;

@end


@implementation GSShader

- (id)initWithVertexShaderSource:(NSString *)vert
            fragmentShaderSource:(NSString *)frag;
{
    self = [super init];
    if (self) {
        // Initialization code here.
        handle = glCreateProgram();
        linked = NO;
        
        [self createShaderWithSource:vert type:GL_VERTEX_SHADER];
        [self createShaderWithSource:frag type:GL_FRAGMENT_SHADER];
        [self link];
        assert(checkGLErrors() == 0);
    }
    
    return self;
}


- (void)bind
{
    glUseProgram(handle);
}


- (void)unbind
{
    glUseProgram(0);
}


- (void)bindUniformWithNSString:(NSString *)name val:(GLint)val
{
    const GLchar *nameCStr = [name cStringUsingEncoding:NSMacOSRomanStringEncoding];
    glUniform1i(glGetUniformLocation(handle, nameCStr), val);
    assert(checkGLErrors() == 0);
}

@end


@implementation GSShader (Private)

/* For OpenGL, build a C array where each element is a line (string) in the shader source.
 * Caller must free the returned array. Strings in the array will be autoreleased.
 * The length of the array is returned in length.
 */
- (const GLchar **)buildSourceStringsArray:(NSString *)source 
                                    length:(GLsizei *)length
{
    NSArray *lines = [source componentsSeparatedByString: @"\n"];
    NSUInteger count = [lines count];
    
    const GLchar **src = malloc(count * sizeof(const GLchar *));
    if(!src) {
        [NSException raise:@"Out of memory" format:@"Failed to malloc memory for src"];
    }
    
    NSEnumerator *e = [lines objectEnumerator];
    id object = nil;
    for(NSUInteger i = 0; (i < count) && (object = [e nextObject]); ++i)
    {
        src[i] = [object cStringUsingEncoding:NSMacOSRomanStringEncoding];
    }
    
    [lines release];
    
    (*length) = (GLsizei)count;
    return src;
}


- (NSString *)getShaderInfoLog:(GLuint)shader
{
    GLint errorLogLen = 0;
    
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &errorLogLen);
    
    char *buffer = malloc(errorLogLen);
    if(!buffer) {
        [NSException raise:@"Out of memory"
                    format:@"Failed to malloc memory for shader info log."];
    }
    
    glGetShaderInfoLog(shader, errorLogLen, NULL, buffer);
    
    NSString *infoLogStr = [NSString stringWithCString:buffer
                                              encoding:NSMacOSRomanStringEncoding];
    
    free(buffer);
    
    return infoLogStr;
}


- (NSString *)getProgramInfoLog:(GLuint)program
{
    GLint errorLogLen = 0;
    
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &errorLogLen);
    
    char *buffer = malloc(errorLogLen);
    if(!buffer) {
        [NSException raise:@"Out of memory"
                    format:@"Failed to malloc memory for program info log."];
    }
    
    glGetProgramInfoLog(program, errorLogLen, NULL, buffer);
    
    NSString *infoLogStr = [NSString stringWithCString:buffer
                                              encoding:NSMacOSRomanStringEncoding];
    
    free(buffer);
    
    return infoLogStr;
}


- (BOOL)wasShaderCompileSuccessful:(GLuint)shader
{
    GLint status = 0;
    
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    
    // if compilation failed, print the log
    if(!status) {
        NSString *infoLog = [self getShaderInfoLog:shader];
        
        NSLog(@"Failed to compile shader object:\n%@", infoLog);
        [infoLog release];
        
        return NO;
    } else {
        return YES;
    }
}


- (BOOL)wasProgramLinkSuccessful:(GLuint)program
{
    GLint status = 0;
    
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    
    // if compilation failed, print the log
    if(!status) {
        NSString *infoLog = [self getShaderInfoLog:program];
        NSLog(@"Failed to link shader program:\n%@", infoLog);
        [infoLog release];
        return NO;
    } else {
        return YES;
    }
}


- (void)createShaderWithSource:(NSString *)sourceString
type:(GLenum)type
{
    const GLchar *src = [sourceString cStringUsingEncoding:NSMacOSRomanStringEncoding];
    
    GLuint shader = glCreateShader(type);
    glAttachShader(handle, shader);
    glShaderSource(shader, 1, &src, NULL);
    glCompileShader(shader);
    
    [self wasShaderCompileSuccessful:shader];
}


- (void)link
{
    glLinkProgram(handle);
    linked = [self wasProgramLinkSuccessful:handle];
}

@end
