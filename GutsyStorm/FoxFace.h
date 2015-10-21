//
//  FoxFace.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FoxFace : NSObject

@property (readonly) BOOL eligibleForOmission;
@property (copy) NSArray *vertexList;
@property (readonly) face_t correspondingCubeFace;

+ (FoxFace *)faceWithQuad:(NSArray *)vertices correspondingCubeFace:(face_t)face;
+ (FoxFace *)faceWithTri:(NSArray *)vertices correspondingCubeFace:(face_t)face;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithVertices:(NSArray *)vertices
           correspondingCubeFace:(face_t)face
             eligibleForOmission:(BOOL)omittable NS_DESIGNATED_INITIALIZER;

@end
