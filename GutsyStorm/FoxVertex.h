//
//  FoxVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxBoxedVector.h"

struct fox_vertex
{
    GLfloat position[3];
    GLubyte color[4];
    GLbyte normal[3];
    GLshort texCoord[3];
};


@interface FoxVertex : NSObject

@property (assign, nonatomic) struct fox_vertex v;

+ (FoxVertex *)vertexWithPosition:(vector_float3)position
                          normal:(vector_long3)normal
                        texCoord:(vector_long3)texCoord;

+ (FoxVertex *)vertexWithVertex:(struct fox_vertex *)pv;

- (instancetype)initWithVertex:(struct fox_vertex *)pv;

- (instancetype)initWithPosition:(vector_float3)position
                          normal:(vector_long3)normal
                        texCoord:(vector_long3)texCoord;

- (vector_float3)position;

@end
