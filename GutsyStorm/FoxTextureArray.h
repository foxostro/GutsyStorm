//
//  FoxTextureArray.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

@interface FoxTextureArray : NSObject

- (nullable instancetype)initWithImagePath:(nonnull NSString *)path numTextures:(GLuint)numTextures;
- (void)bind;
- (void)unbind;

@end
