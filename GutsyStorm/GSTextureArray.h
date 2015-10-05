//
//  GSTextureArray.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

@interface GSTextureArray : NSObject

- (instancetype)initWithImagePath:(NSString *)path numTextures:(GLuint)numTextures;
- (void)bind;
- (void)unbind;

@end
