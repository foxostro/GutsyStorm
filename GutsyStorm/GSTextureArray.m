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
}

- (nonnull instancetype)initWithImage:(nonnull NSImage *)srcImage
                             tileSize:(NSSize)tileSize
                           tileBorder:(NSUInteger)border
{
    NSParameterAssert(srcImage);

    if (self = [super init]) {
        // TODO: Use NSBitmapRep or CGImage throughout to avoid the HiDPI pixel doubling crap that NSImage is doing here.
        
        NSSize imageSize = srcImage.size;
        NSSize step = NSMakeSize(truncf(tileSize.width + border), truncf(tileSize.height + border));
        int numColumns = (imageSize.width-border)/step.width;
        int numRows = (imageSize.height-border)/step.height;
        int numTiles = numColumns * numRows;
        NSSize dstSize = NSMakeSize(tileSize.width, tileSize.height * numTiles);
        NSImage *dstImage = [[NSImage alloc] initWithSize:dstSize];
        
        [dstImage recommendedLayerContentsScale:1.0f];
        [dstImage lockFocus];
        
        for(NSPoint src = NSMakePoint(0, 0), dst = NSMakePoint(0, 0); src.y < (imageSize.height-1); src.y += step.height)
        {
            for(src.x = 0; src.x < (imageSize.width-1); src.x += step.width, dst.y += tileSize.height)
            {
                [srcImage drawAtPoint:dst
                             fromRect:NSMakeRect(imageSize.width - src.x -1 - tileSize.width,
                                                 src.y + 1,
                                                 tileSize.width,
                                                 tileSize.height)
                            operation:NSCompositeSourceOver
                             fraction:1.0f];
            }
        }
        
        NSRect rect = NSMakeRect(0.0, 0.0, dstSize.width, dstSize.height);
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];

        [dstImage unlockFocus];
        
        {
            NSData *imageData = [dstImage TIFFRepresentation];
            NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
            imageData = [imageRep representationUsingType:NSPNGFileType properties:@{}];
            
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
            NSString *desktopPath = [paths objectAtIndex:0];
            NSString *dstPath = [desktopPath stringByAppendingPathComponent:@"image.png"];
            [imageData writeToFile:dstPath atomically:NO];
            
            NSError *error = nil;
            if (![imageData writeToFile:dstPath options:NSDataWritingAtomic error:&error]) {
                NSLog(@"error: %@", error);
            }
        }
        
        GLenum format = [bitmap hasAlpha] ? GL_RGBA : GL_RGB;

        glGenTextures(1, &_handle);        
        glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, _handle);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_T, GL_REPEAT);
        
        glTexImage3D(GL_TEXTURE_2D_ARRAY_EXT, 0, format,
                     tileSize.width*2, tileSize.height*2, numTiles,
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
