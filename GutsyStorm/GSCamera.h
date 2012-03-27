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
#import "GSFrustum.h"

@interface GSCamera : NSObject
{
	float cameraSpeed, cameraRotSpeed;
	GSQuaternion cameraRot;
	GSVector3 cameraEye, cameraCenter, cameraUp;
    GSFrustum *frustum;
}

@property (readonly, nonatomic) GSVector3 cameraEye;
@property (retain) GSFrustum *frustum;


- (void)updateCameraLookVectors;
- (void)resetCamera;
- (void)submitCameraTransform;
- (BOOL)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
										   keysDown:(NSDictionary*)keysDown
										mouseDeltaX:(int)mouseDeltaX
										mouseDeltaY:(int)mouseDeltaY
								   mouseSensitivity:(float)mouseSensitivity;
- (void)moveToPosition:(GSVector3)p;
- (void)reshapeWithBounds:(NSRect)bounds
                      fov:(float)fov
                    nearD:(float)nearD
                     farD:(float)farD;

@end
