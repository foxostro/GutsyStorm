//
//  GSCamera.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSFrustum.h"

#define CAMERA_MOVED  (1)
#define CAMERA_TURNED (2)

@interface GSCamera : NSObject

@property (readonly, nonatomic) GLKVector3 cameraEye;
@property (readonly, nonatomic) GLKVector3 cameraCenter;
@property (readonly, nonatomic) GLKVector3 cameraUp;
@property (readonly, nonatomic) GLKQuaternion cameraRot;
@property (retain) GSFrustum *frustum;

- (void)updateCameraLookVectors;
- (void)resetCamera;
- (void)submitCameraTransform;
- (unsigned)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
                                               keysDown:(NSDictionary*)keysDown
                                            mouseDeltaX:(int)mouseDeltaX
                                            mouseDeltaY:(int)mouseDeltaY
                                       mouseSensitivity:(float)mouseSensitivity;
- (void)moveToPosition:(GLKVector3)p;
- (void)setCameraRot:(GLKQuaternion)rot;
- (void)reshapeWithBounds:(NSRect)bounds
                      fov:(float)fov
                    nearD:(float)nearD
                     farD:(float)farD;

@end
