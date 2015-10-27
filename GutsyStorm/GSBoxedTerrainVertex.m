//
//  GSGeneralVertex.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "GSBoxedTerrainVertex.h"

@implementation GSBoxedTerrainVertex

+ (GSBoxedTerrainVertex *)vertexWithPosition:(vector_float3)position
                          normal:(vector_long3)normal
                        texCoord:(vector_long3)texCoord
{
    return [[GSBoxedTerrainVertex alloc] initWithPosition:position normal:normal texCoord:texCoord];
}

+ (GSBoxedTerrainVertex *)vertexWithVertex:(GSTerrainVertex *)pv
{
    return [[GSBoxedTerrainVertex alloc] initWithVertex:pv];
}

- (instancetype)initWithVertex:(GSTerrainVertex *)pv
{
    assert(pv);
    
    self = [super init];
    if (self) {
        _v = *pv;
    }

    return self;
}

- (instancetype)initWithPosition:(vector_float3)position
                          normal:(vector_long3)normal
                        texCoord:(vector_long3)texCoord
{
    self = [super init];
    if (self) {
        _v.position[0] = position.x;
        _v.position[1] = position.y;
        _v.position[2] = position.z;

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

- (vector_float3)position
{
    return (vector_float3){_v.position[0], _v.position[1], _v.position[2]};
}

@end
