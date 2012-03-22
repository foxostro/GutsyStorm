//
//  GSCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

@interface GSCube : NSObject
{
	GLuint vboCubeVerts, vboCubeNorms, vboCubeTexCoords;
}

- (void)draw;
- (void)generateVBO;

@end
