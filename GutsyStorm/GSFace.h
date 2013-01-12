//
//  GSFace.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSFace : NSObject

@property (copy) NSArray *vertexList;
@property (copy) NSArray *reversedVertexList;

+ (GSFace *)faceWithVertices:(NSArray *)vertices;

- (id)initWithVertices:(NSArray *)vertices;

@end
