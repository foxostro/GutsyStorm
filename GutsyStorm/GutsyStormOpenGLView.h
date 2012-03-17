//
//  GutsyStormOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface GutsyStormOpenGLView : NSOpenGLView
{
	GLuint vboCubeVerts;
}

- (void)drawDebugCubeAtX:(float)x
					   Y:(float)y
					   Z:(float)z;

@end
