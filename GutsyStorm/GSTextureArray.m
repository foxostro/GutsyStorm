//
//  GSTextureArray.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSTextureArray.h"

extern int checkGLErrors(void);

@implementation GSTextureArray

- (id)initWithImagePath:(NSString *)path
            numTextures:(GLuint)numTextures
{
    self = [super init];
    if (self) {
        // Initialization code here.
        NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithContentsOfFile:path];
        bounds = NSMakeRect(0, 0, [bitmap size].width, [bitmap size].height / numTextures);
        
        GLenum format = [bitmap hasAlpha] ? GL_RGBA : GL_RGB;
		
		// Degamma the input
		// XXX: Do this offline and bake into the texture itself.
		size_t bpp = [bitmap hasAlpha] ? 4 : 3;
		const float gamma = 2.2;
		unsigned char * data = [bitmap bitmapData];
		for(size_t x = 0; x < [bitmap size].width; ++x)
		{
			for(size_t y = 0; y < [bitmap size].height; ++y)
			{
				size_t idx = 0;
				
				idx = x*bpp + y*bounds.size.width*bpp;
				
				for(size_t i = 0; i < bpp; ++i)
				{
					float val = MAX(0, MIN(1, powf(data[idx+i] / 255.0, gamma)));
					data[idx+i] = floorf(val * 255.0);
				}
			}
		}
        
        glGenTextures(1, &handle);        
        glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, handle);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glTexImage3D(GL_TEXTURE_2D_ARRAY_EXT, 0, format,
                     bounds.size.width, bounds.size.height, numTextures,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, [bitmap bitmapData]);
		
        glGenerateMipmap(GL_TEXTURE_2D_ARRAY_EXT);
        assert(checkGLErrors() == 0);
    }
    
    return self;
}


- (void)bind
{
    glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, handle);
}


- (void)unbind
{
    glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, 0);
}


- (void)dealloc
{
    glDeleteTextures(1, &handle);
	[super dealloc];
}

@end
