//
//  GSFace.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSBuffer.h" // for buffer_element_t, needed by Voxel.h
#import "Voxel.h" // for face_t, needed by GSFace.h
#import "GSFace.h"
#import "GSVertex.h"

@implementation GSFace

+ (GSFace *)faceWithVertices:(NSArray *)vertices correspondingCubeFace:(face_t)face
{
    return [[GSFace alloc] initWithVertices:vertices correspondingCubeFace:face];
}

- (BOOL)determineEligibilityForOmission:(NSArray *)vertices
{
    assert(([vertices count] == 4) && "Only Quadrilaterals are supported at the moment.");

    // The face is eligible for omission if it fits exactly into a cube face. (i.e. unit area)
    GLKVector3 a = [((GSVertex *)[vertices objectAtIndex:0]) position];
    GLKVector3 b = [((GSVertex *)[vertices objectAtIndex:1]) position];
    GLKVector3 c = [((GSVertex *)[vertices objectAtIndex:2]) position];
    GLKVector3 d = [((GSVertex *)[vertices objectAtIndex:3]) position];
    
    GLKVector3 ba = GLKVector3Subtract(b, a);
    GLKVector3 bc = GLKVector3Subtract(b, c);
    float area1 = GLKVector3Length(GLKVector3CrossProduct(ba, bc));
    
    GLKVector3 da = GLKVector3Subtract(d, a);
    GLKVector3 dc = GLKVector3Subtract(d, c);
    float area2 = GLKVector3Length(GLKVector3CrossProduct(da, dc));
    
    return fabsf(area1+area2-2.0f) < FLT_EPSILON;
}

- (id)initWithVertices:(NSArray *)vertices correspondingCubeFace:(face_t)face
{
    self = [super init];
    if (self) {
        assert(([vertices count] == 4) && "Only Quadrilaterals are supported at the moment.");
        _vertexList = vertices;
        _correspondingCubeFace = face;
        _eligibleForOmission = [self determineEligibilityForOmission:vertices];
    }

    return self;
}

@end
