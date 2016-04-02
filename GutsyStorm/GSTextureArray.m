//
//  GSTextureArray.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSTextureArray.h"
#import <OpenGL/gl.h>

extern int checkGLErrors(void);

@implementation GSTextureArray
{
    GLuint _handle;
    NSRect _bounds;
}

- (instancetype)initWithImagePath:(NSString *)path numTextures:(NSUInteger)numTextures
{
    self = [super init];
    if (self) {
        // Initialization code here.
        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)[NSBitmapImageRep imageRepWithContentsOfFile:path];

        if (!bitmap) {
            NSString *s = [NSString stringWithFormat:@"Failed to load \"%@\" and no way to handle it here.", path];
            @throw [NSException exceptionWithName:NSGenericException reason:s userInfo:nil];
        }

        _bounds = NSMakeRect(0, 0, [bitmap size].width, [bitmap size].height / numTextures);
        
        GLenum format = [bitmap hasAlpha] ? GL_RGBA : GL_RGB;
        
        glGenTextures(1, &_handle);        
        glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, _handle);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glTexImage3D(GL_TEXTURE_2D_ARRAY_EXT, 0, format,
                     _bounds.size.width, _bounds.size.height, (GLuint)numTextures,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, [bitmap bitmapData]);
        
        glGenerateMipmap(GL_TEXTURE_2D_ARRAY_EXT);
        assert(checkGLErrors() == 0);
    }
    
    return self;
}

- (void)bind
{
    glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, _handle);
}

- (void)unbind
{
    glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, 0);
}

- (void)dealloc
{
    glDeleteTextures(1, &_handle);
}

@end
