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
{
    struct vertex v;
}

@property (assign, nonatomic) struct vertex v;

- (id)initWithVertex:(struct vertex *)pv;

@end
