//
//  GSRenderTexture.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSRenderTexture.h"

@implementation GSRenderTexture

@synthesize dimensions;
@synthesize isCubeMap;


- (id)initWithDimensions:(NSRect)_dimensions isCubeMap:(BOOL)_isCubeMap
{
    self = [super init];
    if(self) {
        // Initialization code here.
		dimensions = _dimensions;
		width = dimensions.size.width;
		height = dimensions.size.height;
		originalViewport[0] = originalViewport[1] = originalViewport[2] = originalViewport[3] = 0;
        isCubeMap = _isCubeMap;
        
        glGenTextures(1, &texID);
        
        if(isCubeMap) {
            glBindTexture(GL_TEXTURE_CUBE_MAP, texID);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+0, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+1, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+2, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+3, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+4, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X+5, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            
            // allocate a framebuffer object
            glGenFramebuffers(1, &fbo);
            glBindFramebuffer(GL_FRAMEBUFFER_EXT, fbo);            
            glFramebufferTexture2D(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_CUBE_MAP_POSITIVE_X, texID, 0);
            
            // allocate a renderbuffer for our depth buffer that is the same size as the texture
            glGenRenderbuffers(1, &depthBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);            
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer);
        } else {
            // allocate the texture that we will render into
            glBindTexture(GL_TEXTURE_2D, texID);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
            
            // allocate a framebuffer object
            glGenFramebuffers(1, &fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texID, 0);
            
            // allocate a renderbuffer for our depth buffer that is the same size as the texture
            glGenRenderbuffers(1, &depthBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer);
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
    glDeleteTextures(1, &texID);
    glDeleteRenderbuffers(1, &depthBuffer);
    glDeleteFramebuffers(1, &fbo);
}


- (void)startRender
{
    assert(!isCubeMap);
	glGetIntegerv(GL_VIEWPORT, originalViewport);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glGenerateMipmap(GL_TEXTURE_2D); // generate all mipmaps now
	glViewport(0, 0, width, height);
}


- (void)startRenderForCubeFace:(unsigned)face
{
    assert(isCubeMap);
    assert(face >= 0 && face <= 5);
    
	glGetIntegerv(GL_VIEWPORT, originalViewport);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, texID, 0);
	glViewport(0, 0, width, height);
}


- (void)finishRender
{
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glViewport(originalViewport[0], originalViewport[1], originalViewport[2], originalViewport[3]);
}


- (void)bind
{
    glActiveTexture(GL_TEXTURE0);
    
	if(isCubeMap) {
        glBindTexture(GL_TEXTURE_CUBE_MAP, texID);
    } else {
        glBindTexture(GL_TEXTURE_2D, texID);
    }
}


- (void)unbind
{
    glActiveTexture(GL_TEXTURE0);
    
	if(isCubeMap) {
        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    } else {
        glBindTexture(GL_TEXTURE_2D, 0);
    }
}


@end
