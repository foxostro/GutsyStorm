//
//  GSCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>

@interface GSCube : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(NSOpenGLContext *)context NS_DESIGNATED_INITIALIZER;
- (void)draw;

@end
