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

+ (GSVertex *)vertexWithPosition:(GLKVector3)position
                          normal:(GSIntegerVector3)normal
                        texCoord:(GSIntegerVector3)texCoord
{
    return [[GSVertex alloc] initWithPosition:position normal:normal texCoord:texCoord];
}

+ (GSVertex *)vertexWithVertex:(struct vertex *)pv
{
    return [[GSVertex alloc] initWithVertex:pv];
}

- (instancetype)initWithVertex:(struct vertex *)pv
{
    assert(pv);
    
    self = [super init];
    if (self) {
        _v = *pv;
    }

    return self;
}

- (instancetype)initWithPosition:(GLKVector3)position
                          normal:(GSIntegerVector3)normal
                        texCoord:(GSIntegerVector3)texCoord
{
    self = [super init];
    if (self) {
        _v.position[0] = position.v[0];
        _v.position[1] = position.v[1];
        _v.position[2] = position.v[2];

        _v.normal[0] = normal.x;
        _v.normal[1] = normal.y;
        _v.normal[2] = normal.z;

        _v.texCoord[0] = texCoord.x;
        _v.texCoord[1] = texCoord.y;
        _v.texCoord[2] = texCoord.z;

        _v.color[0] = 255;
        _v.color[1] = 255;
        _v.color[2] = 255;
        _v.color[3] = 255;
    }

    return self;
}

- (GLKVector3)position
{
    return GLKVector3Make(_v.position[0], _v.position[1], _v.position[2]);
}

@end
