//
//  FoxFace.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>


@class GSBoxedTerrainVertex;


@interface FoxFace : NSObject

@property (readonly) BOOL eligibleForOmission;
@property (copy) NSArray<GSBoxedTerrainVertex *> *vertexList;
@property (readonly) GSVoxelFace correspondingCubeFace;

+ (FoxFace *)faceWithQuad:(NSArray<GSBoxedTerrainVertex *> *)vertices correspondingCubeFace:(GSVoxelFace)face;
+ (FoxFace *)faceWithTri:(NSArray<GSBoxedTerrainVertex *> *)vertices correspondingCubeFace:(GSVoxelFace)face;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithVertices:(NSArray<GSBoxedTerrainVertex *> *)vertices
           correspondingCubeFace:(GSVoxelFace)face
             eligibleForOmission:(BOOL)omittable NS_DESIGNATED_INITIALIZER;

@end
