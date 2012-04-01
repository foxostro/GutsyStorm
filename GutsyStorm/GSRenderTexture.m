//
//  GSRenderTexture.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSRenderTexture.h"

@implementation GSRenderTexture

- (id)initWithDimensions:(NSRect)dimensions
{
    self = [super init];
    if (self) {
        // Initialization code here.
		width = dimensions.size.width;
		height = dimensions.size.height;
		originalViewport[0] = originalViewport[1] = originalViewport[2] = originalViewport[3] = 0;
		
		// allocate the texture that we will render into
		glGenTextures(1, &texID);
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
		
		if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
			[NSException raise:@"OpenGL Error" format:@"Failed to create complete framebuffer."];
		}
			
		//  unbind our framebuffer, return to default state
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
	glGetIntegerv(GL_VIEWPORT, originalViewport);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glGenerateMipmap(GL_TEXTURE_2D); // generate all mipmaps now
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
	glBindTexture(GL_TEXTURE_2D, texID);
}


- (void)unbind
{	
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, 0);
}


@end
