//
//  GSVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSBoxedVector.h"

struct vertex
{
    GLfloat position[3];
    GLubyte color[4];
    GLbyte normal[3];
    GLshort texCoord[3];
};


@interface GSVertex : NSObject

@property (assign, nonatomic) struct vertex v;

+ (GSVertex *)vertexWithPosition:(GLKVector3)position
                          normal:(GSIntegerVector3)normal
                        texCoord:(GSIntegerVector3)texCoord;

+ (GSVertex *)vertexWithVertex:(struct vertex *)pv;

- (id)initWithVertex:(struct vertex *)pv;

- (id)initWithPosition:(GLKVector3)position
                normal:(GSIntegerVector3)normal
              texCoord:(GSIntegerVector3)texCoord;

- (GLKVector3)position;

@end
