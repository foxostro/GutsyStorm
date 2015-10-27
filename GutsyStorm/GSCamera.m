//
//  GSCamera.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSCamera.h"
#import "GSIntegerVector3.h"
#import "GSTerrainBuffer.h" // for GSTerrainBufferElement, needed by Voxel.h
#import "GSVoxel.h"
#import "GSQuaternion.h"

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

// Updated the camera look vectors.
- (void)updateCameraLookVectors
{
    _cameraCenter = _cameraEye + vector_normalize(quaternion_rotate_vector(_cameraRot, vector_make(0,0,-1)));
    _cameraUp = vector_normalize(quaternion_rotate_vector(_cameraRot, vector_make(0,1,0)));

    vector_float3 ev = _cameraEye;
    vector_float3 cv = _cameraCenter;
    vector_float3 uv = _cameraUp;
    vector_float3 n = vector_normalize(ev + -cv);
    vector_float3 u = vector_normalize(vector_cross(uv, n));
    vector_float3 v = vector_cross(n, u);

    matrix_float4x4 m = {
        (vector_float4){u.x, u.y, u.z, vector_dot(-u, ev)},
        (vector_float4){v.x, v.y, v.z, vector_dot(-v, ev)},
        (vector_float4){n.x, n.y, n.z, vector_dot(-n, ev)},
        (vector_float4){0,   0,   0,   1}
    };

    _modelViewMatrix = m;
}

// Set the default camera and reset camera properties.
- (void)resetCamera
{    
    _ceilingHeight = CHUNK_SIZE_Y;
    _cameraSpeed = 10.0;
    _cameraRotSpeed = 1.0;
    _cameraEye = vector_make(0.0f, 0.0f, 0.0f);
    _cameraCenter = vector_make(0.0f, 0.0f, -1.0f);
    _cameraUp = vector_make(0.0f, 1.0f, 0.0f);
    _cameraRot = quaternion_make_with_angle_and_axis(0, 0, 1, 0);
    [self updateCameraLookVectors];
}

// Handles user input to control a flying camera.
- (unsigned)handleUserInputForFlyingCameraWithDeltaTime:(float)dt
                                               keysDown:(NSDictionary<NSNumber *, NSNumber *> *)keysDown
                                            mouseDeltaX:(int)mouseDeltaX
                                            mouseDeltaY:(int)mouseDeltaY
                                       mouseSensitivity:(float)mouseSensitivity
{
    unsigned cameraModifiedFlags = 0;

    if([keysDown[@('w')] boolValue]) {
        vector_float3 velocity = quaternion_rotate_vector(_cameraRot, vector_make(0, 0, -_cameraSpeed*dt));
        _cameraEye = _cameraEye + vector_make(velocity.x, velocity.y, velocity.z);
        cameraModifiedFlags |= CAMERA_MOVED;
    } else if([keysDown[@('s')] boolValue]) {
        vector_float3 velocity = quaternion_rotate_vector(_cameraRot, vector_make(0, 0, _cameraSpeed*dt));
        _cameraEye = _cameraEye + vector_make(velocity.x, velocity.y, velocity.z);
        cameraModifiedFlags |= CAMERA_MOVED;
    }

    if([keysDown[@('a')] boolValue]) {
        vector_float3 velocity = quaternion_rotate_vector(_cameraRot, vector_make(-_cameraSpeed*dt, 0, 0));
        _cameraEye = _cameraEye + vector_make(velocity.x, velocity.y, velocity.z);
        cameraModifiedFlags |= CAMERA_MOVED;
    } else if([keysDown[@('d')] boolValue]) {
        vector_float3 velocity = quaternion_rotate_vector(_cameraRot, vector_make(_cameraSpeed*dt, 0, 0));
        _cameraEye = _cameraEye + vector_make(velocity.x, velocity.y, velocity.z);
        cameraModifiedFlags |= CAMERA_MOVED;
    }

    if([keysDown[@('j')] boolValue]) {
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(_cameraRotSpeed*dt, 0, 1, 0);
        _cameraRot = quaternion_multiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    } else if([keysDown[@('l')] boolValue]) {
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(-_cameraRotSpeed*dt, 0, 1, 0);
        _cameraRot = quaternion_multiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if([keysDown[@('i')] boolValue]) {
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(-_cameraRotSpeed*dt, 1, 0, 0);
        _cameraRot = quaternion_multiply(_cameraRot, deltaRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    } else if([keysDown[@('k')] boolValue]) {
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(_cameraRotSpeed*dt, 1, 0, 0);
        _cameraRot = quaternion_multiply(_cameraRot, deltaRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if(mouseDeltaX != 0) {
        float mouseDirectionX = -mouseDeltaX/mouseSensitivity/dt;
        float angle = mouseDirectionX*dt;
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(angle, 0, 1, 0);
        _cameraRot = quaternion_multiply(deltaRot, _cameraRot);
        cameraModifiedFlags |= CAMERA_TURNED;
    }

    if(mouseDeltaY != 0) {
        float mouseDirectionY = -mouseDeltaY/mouseSensitivity/dt;
        float angle = mouseDirectionY*dt;
        vector_float4 deltaRot = quaternion_make_with_angle_and_axis(angle, 1, 0, 0);
        _cameraRot = quaternion_multiply(_cameraRot, deltaRot);
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

- (void)moveToPosition:(vector_float3)p
{
    _cameraEye = p;
    [self updateCameraLookVectors];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
}

- (void)reshapeWithSize:(CGSize)size fov:(float)fovyRadians nearD:(float)nearZ farD:(float)farZ
{
    const float ratio = size.width / size.height;
    [_frustum setCamInternalsWithAngle:fovyRadians ratio:ratio nearD:nearZ farD:farZ];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];

    float aspect = size.width / size.height;
    float cotan = 1.0f / tanf(fovyRadians / 2.0f);

    _projectionMatrix = (matrix_float4x4){
        (vector_float4){cotan / aspect, 0,     0,                               0},
        (vector_float4){0,              cotan, 0,                               0},
        (vector_float4){0,              0,     (farZ + nearZ) / (nearZ - farZ), (2.0f * farZ * nearZ) / (nearZ - farZ)},
        (vector_float4){0,              0,     -1,                              0},
    };;
}

- (void)setCameraRot:(vector_float4)rot
{
    _cameraRot = rot;
    [self updateCameraLookVectors];
    [_frustum setCamDefWithCameraEye:_cameraEye cameraCenter:_cameraCenter cameraUp:_cameraUp];
}

@end