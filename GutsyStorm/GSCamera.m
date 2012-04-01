//
//  GSCamera.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import "GSCamera.h"

@implementation GSCamera

@synthesize cameraEye;
@synthesize cameraRot;
@synthesize frustum;


- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
		[self resetCamera];
        
        frustum = [[GSFrustum alloc] init];
        [frustum setCamInternalsWithAngle:60.0 ratio:640.0/480.0 nearD:0.1 farD:400.0]; // Set for real later on.
        [frustum setCamDefWithCameraEye:cameraEye cameraCenter:cameraCenter cameraUp:cameraUp];
    }
    
    return self;
}


- (void)dealloc
{
    [frustum release];
}


// Submits the camera transformation to OpenGL.
- (void)submitCameraTransform
{
	gluLookAt(cameraEye.x,    cameraEye.y,    cameraEye.z,
              cameraCenter.x, cameraCenter.y, cameraCenter.z,
              cameraUp.x,     cameraUp.y,     cameraUp.z);
}


// Updated the camera look vectors.
- (void)updateCameraLookVectors
{	
	cameraCenter = GSVector3_Add(cameraEye, GSVector3_Normalize(GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0,0,-1))));	
    cameraUp = GSVector3_Normalize(GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0,1,0)));
}


// Set the default camera and reset camera properties.
- (void)resetCamera
{	
	cameraSpeed = 10.0;
	cameraRotSpeed = 1.0;
	cameraEye = GSVector3_Make(0.0f, 0.0f, 0.0f);
	cameraCenter = GSVector3_Make(0.0f, 0.0f, -1.0f);
	cameraUp = GSVector3_Make(0.0f, 1.0f, 0.0f);
	cameraRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), 0);
	[self updateCameraLookVectors];
}


// Handles user input to control a flying camera.
- (unsigned)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
											   keysDown:(NSDictionary*)keysDown
											mouseDeltaX:(int)mouseDeltaX
											mouseDeltaY:(int)mouseDeltaY
									   mouseSensitivity:(float)mouseSensitivity
{
	unsigned cameraModifiedFlags = 0;
	
	[keysDown retain];

	if([[keysDown objectForKey:[NSNumber numberWithInt:'w']] boolValue]) {
		GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0, 0, -cameraSpeed*dt));
		cameraEye = GSVector3_Add(cameraEye, velocity);
		cameraModifiedFlags |= CAMERA_MOVED;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'s']] boolValue]) {
		GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(0, 0, cameraSpeed*dt));
		cameraEye = GSVector3_Add(cameraEye, velocity);
		cameraModifiedFlags |= CAMERA_MOVED;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'a']] boolValue]) {
		GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(-cameraSpeed*dt, 0, 0));
		cameraEye = GSVector3_Add(cameraEye, velocity);
		cameraModifiedFlags |= CAMERA_MOVED;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'d']] boolValue]) {
		GSVector3 velocity = GSQuaternion_MulByVec(cameraRot, GSVector3_Make(cameraSpeed*dt, 0, 0));
		cameraEye = GSVector3_Add(cameraEye, velocity);
		cameraModifiedFlags |= CAMERA_MOVED;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'j']] boolValue]) {
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'l']] boolValue]) {
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), -cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	}

	if([[keysDown objectForKey:[NSNumber numberWithInt:'i']] boolValue]) {
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), -cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	} else if([[keysDown objectForKey:[NSNumber numberWithInt:'k']] boolValue]) {
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), cameraRotSpeed*dt);
		cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	}

	if(mouseDeltaX != 0) {
		float mouseDirectionX = -mouseDeltaX/mouseSensitivity/dt;
		float angle = mouseDirectionX*dt;
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(0,1,0), angle);
		cameraRot = GSQuaternion_MulByQuat(deltaRot, cameraRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	}

	if(mouseDeltaY != 0) {
		float mouseDirectionY = -mouseDeltaY/mouseSensitivity/dt;
		float angle = mouseDirectionY*dt;
		GSQuaternion deltaRot = GSQuaternion_MakeFromAxisAngle(GSVector3_Make(1,0,0), angle);
		cameraRot = GSQuaternion_MulByQuat(cameraRot, deltaRot);
		cameraModifiedFlags |= CAMERA_TURNED;
	}

	[keysDown release];

	if(cameraModifiedFlags) {
		[self updateCameraLookVectors];
        [frustum setCamDefWithCameraEye:cameraEye cameraCenter:cameraCenter cameraUp:cameraUp];
	}
	
	return cameraModifiedFlags;
}


- (void)moveToPosition:(GSVector3)p
{
    cameraEye = p;
    [self updateCameraLookVectors];
    [frustum setCamDefWithCameraEye:cameraEye cameraCenter:cameraCenter cameraUp:cameraUp];
}


- (void)reshapeWithBounds:(NSRect)bounds fov:(float)fov nearD:(float)nearD farD:(float)farD
{
    const float ratio = bounds.size.width / bounds.size.height;
    [frustum setCamInternalsWithAngle:fov ratio:ratio nearD:nearD farD:farD];
    [frustum setCamDefWithCameraEye:cameraEye cameraCenter:cameraCenter cameraUp:cameraUp];
}

@end
