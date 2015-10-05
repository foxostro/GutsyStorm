//
//  GSRenderTexture.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSRenderTexture.h"
#import <OpenGL/gl.h>

@implementation GSRenderTexture
{
    GLuint _texID;
    GLuint _fbo;
    GLuint _depthBuffer;
    GLuint _width;
    GLuint _height;
    int _originalViewport[4];
}

- (instancetype)initWithDimensions:(NSRect)dimensions isCubeMap:(BOOL)isCubeMap
{
    self = [super init];
    if(self) {
        // Initialization code here.
        _dimensions = dimensions;
        _width = _dimensions.size.width;
        _height = _dimensions.size.height;
        _originalViewport[0] = _originalViewport[1] = _originalViewport[2] = _originalViewport[3] = 0;
        _isCubeMap = isCubeMap;
        
        glGenTextures(1, &_texID);
        
        if(isCubeMap) {
            glBindTexture(GL_TEXTURE_CUBE_MAP, _texID);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+0, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+1, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+2, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+3, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+4, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+5, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            
            // allocate a framebuffer object
            glGenFramebuffers(1, &_fbo);
            glBindFramebuffer(GL_FRAMEBUFFER_EXT, _fbo);            
            glFramebufferTexture2D(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_CUBE_MAP_POSITIVE_X, _texID, 0);
            
            // allocate a renderbuffer for our depth buffer that is the same size as the texture
            glGenRenderbuffers(1, &_depthBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, _depthBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, _width, _height);            
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthBuffer);
        } else {
            // allocate the texture that we will render into
            glBindTexture(GL_TEXTURE_2D, _texID);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, _width, _height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            
            // allocate a framebuffer object
            glGenFramebuffers(1, &_fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texID, 0);
            
            // allocate a renderbuffer for our depth buffer that is the same size as the texture
            glGenRenderbuffers(1, &_depthBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, _depthBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, _width, _height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthBuffer);
        }
        
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            [NSException raise:@"OpenGL Error" format:@"Failed to create complete framebuffer."];
        }
            
        // unbind our framebuffer, return to default state
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    
    return self;
}

- (void)dealloc
{
    glDeleteTextures(1, &_texID);
    glDeleteRenderbuffers(1, &_depthBuffer);
    glDeleteFramebuffers(1, &_fbo);
}

- (void)startRender
{
    assert(!_isCubeMap);
    glGetIntegerv(GL_VIEWPORT, _originalViewport);
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
    glGenerateMipmap(GL_TEXTURE_2D); // generate all mipmaps now
    glViewport(0, 0, _width, _height);
}

- (void)startRenderForCubeFace:(unsigned)face
{
    assert(_isCubeMap);
    assert(face >= 0 && face <= 5);
    
    glGetIntegerv(GL_VIEWPORT, _originalViewport);
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, _texID, 0);
    glViewport(0, 0, _width, _height);
}

- (void)finishRender
{
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(_originalViewport[0], _originalViewport[1], _originalViewport[2], _originalViewport[3]);
}

- (void)bind
{
    glActiveTexture(GL_TEXTURE0);
    
    if(_isCubeMap) {
        glBindTexture(GL_TEXTURE_CUBE_MAP, _texID);
    } else {
        glBindTexture(GL_TEXTURE_2D, _texID);
    }
}

- (void)unbind
{
    glActiveTexture(GL_TEXTURE0);
    
    if(_isCubeMap) {
        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    } else {
        glBindTexture(GL_TEXTURE_2D, 0);
    }
}

@end
