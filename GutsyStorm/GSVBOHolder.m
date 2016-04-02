//
//  GSVBOHolder.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSVBOHolder.h"
#import <OpenGL/gl.h>

@implementation GSVBOHolder
{
    NSOpenGLContext *_glContext;
}

- (instancetype)initWithHandle:(GLuint)handle context:(NSOpenGLContext *)context
{
    if(self = [super init]) {
        _glContext = context;
        _handle = handle;
    }
    return self;
}

- (void)dealloc
{
    NSOpenGLContext *context = _glContext;
    GLuint handle = _handle;

    assert(context);

    dispatch_async(dispatch_get_main_queue(), ^{
        assert(context);
        if(handle) {
            [context makeCurrentContext];
            CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
            glDeleteBuffers(1, &handle);
            CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
        }
    });
}

@end