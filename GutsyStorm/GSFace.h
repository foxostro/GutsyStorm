//
//  GSFace.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>


@class GSBoxedTerrainVertex;


@interface GSFace : NSObject

@property (nonatomic, readonly) BOOL eligibleForOmission;
@property (nonatomic, copy, nonnull) NSArray<GSBoxedTerrainVertex *> *vertexList;
@property (nonatomic, readonly) GSVoxelFace correspondingCubeFace;

+ (nonnull GSFace *)faceWithQuad:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
           correspondingCubeFace:(GSVoxelFace)face
             eligibleForOmission:(BOOL)omittable;

+ (nonnull GSFace *)faceWithTri:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
          correspondingCubeFace:(GSVoxelFace)face;

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithVertices:(nonnull NSArray<GSBoxedTerrainVertex *> *)vertices
                    correspondingCubeFace:(GSVoxelFace)face
                      eligibleForOmission:(BOOL)omittable NS_DESIGNATED_INITIALIZER;

@end
