//
//  GSCamera.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSQuaternion.h"
#import "GSVector3.h"

@interface GSCamera : NSObject
{
	float cameraSpeed, cameraRotSpeed;
	GSQuaternion cameraRot;
	GSVector3 cameraEye, cameraCenter, cameraUp;
}

- (void)updateCameraLookVectors;
- (void)resetCamera;
- (void)submitCameraTransform;
- (void)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
										   keysDown:(NSDictionary*)keysDown
										mouseDeltaX:(int)mouseDeltaX
										mouseDeltaY:(int)mouseDeltaY
								   mouseSensitivity:(float)mouseSensitivity;
- (void)moveToPosition:(GSVector3)p;

@end
