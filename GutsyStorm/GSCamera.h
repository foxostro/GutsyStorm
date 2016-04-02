//
//  GSCamera.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSFrustum.h"

#define CAMERA_MOVED  (1)
#define CAMERA_TURNED (2)

@interface GSCamera : NSObject

@property (readonly, nonatomic) vector_float3 cameraEye;
@property (readonly, nonatomic) vector_float3 cameraCenter;
@property (readonly, nonatomic) vector_float3 cameraUp;
@property (readonly, nonatomic) vector_float4 cameraRot;
@property (readonly, nonatomic) matrix_float4x4 modelViewMatrix;
@property (readonly, nonatomic) matrix_float4x4 projectionMatrix;
@property (strong, nonatomic, nullable) GSFrustum * frustum;

- (void)updateCameraLookVectors;
- (void)resetCamera;
- (unsigned)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
                                               keysDown:(nonnull NSDictionary<NSNumber *, NSNumber *> *)keysDown
                                            mouseDeltaX:(int)mouseDeltaX
                                            mouseDeltaY:(int)mouseDeltaY
                                       mouseSensitivity:(float)mouseSensitivity;
- (void)moveToPosition:(vector_float3)p;
- (void)setCameraRot:(vector_float4)rot;
- (void)reshapeWithSize:(CGSize)size
                    fov:(float)fov
                  nearD:(float)nearD
                   farD:(float)farD;

@end
