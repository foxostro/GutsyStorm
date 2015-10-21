//
//  FoxTextLabel.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/21/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import "FoxTextLabel.h"
#import "GLString.h"

@implementation FoxTextLabel
{
    GLString *_fpsStringTex;
    NSMutableDictionary<NSString *, id> *_stringAttribs; // attributes for string textures
}

- (nullable instancetype)init
{
    self = [super init];

    if (self) {
        // init fonts for use with strings
        NSFont *font = [NSFont fontWithName:@"Helvetica" size:12.0];
        _stringAttribs = [NSMutableDictionary<NSString *, id> dictionary];
        _stringAttribs[NSFontAttributeName] = font;
        _stringAttribs[NSForegroundColorAttributeName] = [NSColor whiteColor];
        _text = @"FPS: ?";
        _fpsStringTex = [[GLString alloc] initWithString:_text
                                          withAttributes:_stringAttribs
                                           withTextColor:[NSColor whiteColor]
                                            withBoxColor:[NSColor colorWithDeviceRed:0.3f
                                                                               green:0.3f
                                                                                blue:0.3f
                                                                               alpha:1.0f]
                                         withBorderColor:[NSColor colorWithDeviceRed:0.7f
                                                                               green:0.7f
                                                                                blue:0.7f
                                                                               alpha:1.0f]];
    }

    return self;
}

- (void)setText:(NSString *)text
{
    _text = text;
    [_fpsStringTex setString:text withAttributes:_stringAttribs];
}

- (void)drawAtPoint:(NSPoint)point
{
    [_fpsStringTex drawAtPoint:NSMakePoint(10.0f, 10.0f) withModelViewProjectionMatrix:_projectionMatrix];
}

@end
