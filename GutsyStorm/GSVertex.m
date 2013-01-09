//
//  GSVertex.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <OpenGL/OpenGL.h>
#import <GLKit/GLKMath.h>

#import "GLKVector3Extra.h"
#import "GSVertex.h"

@implementation GSVertex

- (id)initWithVertex:(struct vertex *)pv
{
    assert(pv);
    
    self = [super init];
    if (self) {
        _v = *pv;
    }

    return self;
}

@end
