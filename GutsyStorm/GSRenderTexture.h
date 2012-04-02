//
//  GSRenderTexture.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSRenderTexture : NSObject
{
	GLuint texID;
	GLuint fbo;
	GLuint depthBuffer;
	GLuint width;
	GLuint height;
	int originalViewport[4];
	NSRect dimensions;
}

@property (assign, nonatomic) NSRect dimensions;

- (id)initWithDimensions:(NSRect)dimensions;
- (void)startRender;
- (void)finishRender;
- (void)bind;
- (void)unbind;

@end
