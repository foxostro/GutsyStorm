//
//  GSFace.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSFace.h"

@implementation GSFace

+ (GSFace *)faceWithVertices:(NSArray *)vertices
{
    return [[GSFace alloc] initWithVertices:vertices];
}

- (id)initWithVertices:(NSArray *)vertices
{
    self = [super init];
    if (self) {
        assert(([vertices count] == 4) && "Only Quadrilaterals are supported at the moment.");

        _vertexList = [vertices copy];

        NSMutableArray *reversedVertexList = [NSMutableArray arrayWithCapacity:[_vertexList count]];
        NSEnumerator *enumerator = [_vertexList reverseObjectEnumerator];
        for(id element in enumerator)
        {
            [reversedVertexList addObject:element];
        }
        _reversedVertexList = reversedVertexList;
    }

    return self;
}

@end
