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

- (nonnull instancetype)initWithPath:(nonnull NSString *)path
                            tileSize:(NSSize)tileSize
                          tileBorder:(NSUInteger)border
{
    NSParameterAssert(path);

    if (self = [super init]) {
        CGDataProviderRef dataProvider = CGDataProviderCreateWithFilename([path UTF8String]);
        CGImageRef imageRef = CGImageCreateWithPNGDataProvider(dataProvider, NULL, true, kCGRenderingIntentDefault);

        CGSize step = CGSizeMake(truncf(tileSize.width + border), truncf(tileSize.height + border));
        size_t width = CGImageGetWidth(imageRef);
        size_t height = CGImageGetHeight(imageRef);
        size_t numColumns = (width-border)/step.width;
        size_t numRows = (height-border)/step.height;
        size_t numTiles = numColumns * numRows;
        CGSize dstSize = CGSizeMake(tileSize.width, tileSize.height * numTiles);

        CGContextRef contextRef = CGBitmapContextCreate(NULL, dstSize.width, dstSize.height, 8, dstSize.width * 4,
                                                        CGColorSpaceCreateDeviceRGB(),
                                                        kCGImageAlphaPremultipliedLast);
        
        for(NSPoint src = NSMakePoint(0, 0), dst = NSMakePoint(0, 0); src.y < (height-1); src.y += step.height)
        {
            for(src.x = 0; src.x < (width-1); src.x += step.width, dst.y += tileSize.height)
            {
                CGRect srcRect = CGRectMake(width - src.x - 1 - tileSize.width,
                                            height - src.y - 1 - tileSize.height,
                                            tileSize.width,
                                            tileSize.height);
                CGImageRef subTileRef = CGImageCreateWithImageInRect(imageRef, srcRect);
                CGRect dstRect = CGRectMake(dst.x, dst.y, tileSize.width, tileSize.height);
                CGContextDrawImage(contextRef, dstRect, subTileRef);
            }
        }

        glGenTextures(1, &_handle);
        glBindTexture(GL_TEXTURE_2D_ARRAY_EXT, _handle);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D_ARRAY_EXT, GL_TEXTURE_WRAP_T, GL_REPEAT);
        
        glTexImage3D(GL_TEXTURE_2D_ARRAY_EXT, 0, GL_RGBA,
                     tileSize.width, tileSize.height, (GLsizei)numTiles,
                     0, GL_RGBA, GL_UNSIGNED_BYTE,
                     CGBitmapContextGetData(contextRef));

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
