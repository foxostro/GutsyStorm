//
//  GSFace.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainBuffer.h" // for GSTerrainBufferElement, needed by GSVoxel.h
#import "GSVoxel.h" // for GSVoxelFace, needed by GSFace.h
#import "GSFace.h"
#import "GSBoxedTerrainVertex.h"

@implementation GSFace

+ (nonnull NSArray<GSBoxedTerrainVertex *> *)decomposeQuad:(nonnull NSArray<GSBoxedTerrainVertex *> *)verticesIn
{
    NSParameterAssert(verticesIn);
    
    NSArray<GSBoxedTerrainVertex *> *verticesOut = nil;
    NSUInteger count = verticesIn.count;
    
    assert(count == 4 || count == 3);
    
    if (count == 3) {
        verticesOut = verticesIn;
    } else {
        verticesOut = @[ verticesIn[0], verticesIn[1], verticesIn[2],
                         verticesIn[0], verticesIn[2], verticesIn[3] ];
    }
    
    return verticesOut;
}

+ (nonnull GSFace *)faceWithQuad:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
           correspondingCubeFace:(GSVoxelFace)face
             eligibleForOmission:(BOOL)omittable
{
    NSParameterAssert(vertices && vertices.count == 4);
    NSArray<GSBoxedTerrainVertex *> *triangleVertices = [self decomposeQuad:vertices];
    return [[GSFace alloc] initWithVertices:triangleVertices
                      correspondingCubeFace:face
                        eligibleForOmission:omittable];
}

+ (nonnull GSFace *)faceWithTri:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
          correspondingCubeFace:(GSVoxelFace)face
{
    NSParameterAssert(vertices && vertices.count == 3);
    return [[GSFace alloc] initWithVertices:vertices
                      correspondingCubeFace:face
                        eligibleForOmission:NO];
}

- (nonnull instancetype)init
{
    @throw nil;
    return nil;
}

- (nonnull instancetype)initWithVertices:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
                   correspondingCubeFace:(GSVoxelFace)face
                     eligibleForOmission:(BOOL)omittable
{
    NSParameterAssert(vertices);
    NSParameterAssert(face >= 0 && face < FACE_NUM_FACES);

    self = [super init];
    if (self) {
        _vertexList = vertices;
        _correspondingCubeFace = face;
        _eligibleForOmission = omittable;
    }

    return self;
}

@end
