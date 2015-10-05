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
#import <GLKit/GLKMath.h>
#import "GSCamera.h"
#import "GSIntegerVector3.h"
#import "GSBuffer.h" // for buffer_element_t, needed by Voxel.h
#import "Voxel.h"

@implementation GSCamera
{
    float _ceilingHeight;
    float _cameraSpeed;
    float _cameraRotSpeed;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        [self resetCamera];
        
        _frustum = [[GSFrustum alloc] init];
        [_frustum setCamInternalsWithAngle:(60.0*M_PI/180.0) ratio:640.0/480.0 nearD:0.1 farD:1000.0]; // TODO: Set for real later on.
        [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
    }
    
    return self;
}

// Submits the camera transformation to OpenGL.
- (void)submitCameraTransform
{
    glMultMatrixf(GLKMatrix4MakeLookAt(_cameraEye.x,    _cameraEye.y,    _cameraEye.z,
                                       _cameraCenter.x, _cameraCenter.y, _cameraCenter.z,
                                       _cameraUp.x,     _cameraUp.y,     _cameraUp.z).m);
}

// Updated the camera look vectors.
- (void)updateCameraLookVectors
{
    _cameraCenter = GLKVector3Add(_cameraEye, GLKVector3Normalize(GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(0,0,-1))));
    _cameraUp = GLKVector3Normalize(GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(0,1,0)));
}

// Set the default camera and reset camera properties.
- (void)resetCamera
{    
    _ceilingHeight = CHUNK_SIZE_Y;
    _cameraSpeed = 10.0;
    _cameraRotSpeed = 1.0;
    _cameraEye = GLKVector3Make(0.0f, 0.0f, 0.0f);
    _cameraCenter = GLKVector3Make(0.0f, 0.0f, -1.0f);
    _cameraUp = GLKVector3Make(0.0f, 1.0f, 0.0f);
    _cameraRot = GLKQuaternionMakeWithAngleAndAxis(0, 0, 1, 0);
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

    if([keysDown[@('w')] boolValue]) {
        GLKVector3 velocity = GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(0, 0, -_cameraSpeed*dt));
        _cameraEye = GLKVector3Add(_cameraEye, velocity);
        cameraModifiedFlags |= CAMERA_MOVED;
    } else if([keysDown[@('s')] boolValue]) {
        GLKVector3 velocity = GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(0, 0, _cameraSpeed*dt));
        _cameraEye = GLKVector3Add(_cameraEye, velocity);
        cameraModifiedFlags |= CAMERA_MOVED;
    }

    if([keysDown[@('a')] boolValue]) {
        GLKVector3 velocity = GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(-_cameraSpeed*dt, 0, 0));
        _cameraEye = GLKVector3Add(_cameraEye, velocity);
        cameraModifiedFlags |= CAMERA_MOVED;
    } else if([keysDown[@('d')] boolValue]) {
        GLKVector3 velocity = GLKQuaternionRotateVector3(_cameraRot, GLKVector3Make(_cameraSpeed*dt, 0, 0));
        _cameraEye = GLKVector3Add(_cameraEye, velocity);
        cameraModifiedFlags |= CAMERA_MOVED;
    }

    if([keysDown[@('j')] boolValue]) {
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(_cameraRotSpeed*dt, 0, 1, 0);
        _cameraRot = GLKQuaternionMultiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    } else if([keysDown[@('l')] boolValue]) {
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(-_cameraRotSpeed*dt, 0, 1, 0);
        _cameraRot = GLKQuaternionMultiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if([keysDown[@('i')] boolValue]) {
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(-_cameraRotSpeed*dt, 1, 0, 0);
        _cameraRot = GLKQuaternionMultiply(_cameraRot, deltaRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    } else if([keysDown[@('k')] boolValue]) {
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(_cameraRotSpeed*dt, 1, 0, 0);
        _cameraRot = GLKQuaternionMultiply(_cameraRot, deltaRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if(mouseDeltaX != 0) {
        float mouseDirectionX = -mouseDeltaX/mouseSensitivity/dt;
        float angle = mouseDirectionX*dt;
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(angle, 0, 1, 0);
        _cameraRot = GLKQuaternionMultiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if(mouseDeltaY != 0) {
        float mouseDirectionY = -mouseDeltaY/mouseSensitivity/dt;
        float angle = mouseDirectionY*dt;
        GLKQuaternion deltaRot = GLKQuaternionMakeWithAngleAndAxis(angle, 1, 0, 0);
        _cameraRot = GLKQuaternionMultiply(_cameraRot, deltaRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if(cameraModifiedFlags) {
        _cameraEye.y = MIN(_cameraEye.y, _ceilingHeight);
        _cameraEye.y = MAX(_cameraEye.y, 0.0);
        
        [self updateCameraLookVectors];
        [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
    }
    
    return cameraModifiedFlags;
}

- (void)moveToPosition:(GLKVector3)p
{
    _cameraEye = p;
    [self updateCameraLookVectors];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
}

- (void)reshapeWithBounds:(NSRect)bounds fov:(float)fov nearD:(float)nearD farD:(float)farD
{
    const float ratio = bounds.size.width / bounds.size.height;
    [_frustum setCamInternalsWithAngle:fov ratio:ratio nearD:nearD farD:farD];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
}

- (void)setCameraRot:(GLKQuaternion)rot
{
    _cameraRot = rot;
    [self updateCameraLookVectors];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
}

@end