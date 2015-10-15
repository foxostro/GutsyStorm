//
//  GSCube.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class NSOpenGLContext;
@class GSShader;

@interface GSCube : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(NSOpenGLContext *)context shader:(GSShader *)shader NS_DESIGNATED_INITIALIZER;
- (void)draw;

@end
