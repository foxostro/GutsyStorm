//
//  GutsyStormOpenGLView.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import "GutsyStormOpenGLView.h"

@implementation GutsyStormOpenGLView

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	[self prepare];
	return self;
}

- (void)prepare
{
	NSLog(@"prepare");
	
	NSOpenGLContext * ctx = [self openGLContext];
	[ctx makeCurrentContext];
	
	glDisable(GL_LIGHTING);
	glEnable(GL_DEPTH_TEST);
	glClearColor(0.0, 0.0, 0.0, 1.0);
}

- (void)awakeFromNib
{
	NSLog(@"awakeFromNib");
}

- (void)reshape
{
	NSLog(@"reshape");
	NSRect r = [self convertRectToBase:[self bounds]];
	glViewport(0, 0, r.size.width, r.size.height);
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	gluPerspective(60.0, r.size.width/r.size.height, 0.1, 400.0);
	glMatrixMode(GL_MODELVIEW);
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSLog(@"drawRect");
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glFlush();
}

@end
