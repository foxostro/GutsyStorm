//
//  GSVAOHolder.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSVAOHolder.h"
#import <OpenGL/gl.h>

@implementation GSVAOHolder
{
    NSOpenGLContext *_glContext;
}

- (nonnull instancetype)initWithHandle:(GLuint)handle context:(nonnull NSOpenGLContext *)context
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

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        assert(context);
        if(handle) {
            [context makeCurrentContext];
            CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
            glDeleteVertexArraysAPPLE(1, &handle);
            CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
        }
    });
}

@end