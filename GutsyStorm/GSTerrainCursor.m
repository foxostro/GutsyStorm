//
//  GSTerrainCursor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainCursor.h"
#import "GSCamera.h"
#import "GSChunkStore.h"
#import "GSTerrainRayMarcher.h"
#import "GSCube.h"
#import "GSMatrixUtils.h"


@implementation GSTerrainCursor
{
    GSChunkStore *_chunkStore;
    GSCamera *_camera;
    GSTerrainRayMarcher *_rayMarcher;
    GSCube *_cube;
    float _maxPlaceDistance;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithChunkStore:(nonnull GSChunkStore *)chunkStore
                                    camera:(nonnull GSCamera *)camera
                                      cube:(nonnull GSCube *)cube
{
    NSParameterAssert(chunkStore);
    NSParameterAssert(camera);
    NSParameterAssert(cube);

    if (self = [super init]) {
        _chunkStore = chunkStore;
        _camera = camera;
        _cube = cube;
        _rayMarcher = [[GSTerrainRayMarcher alloc] init];
        _cursorIsActive = NO;
        _cursorPos = vector_make(0, 0, 0);
        _cursorPlacePos = vector_make(0, 0, 0);
        _maxPlaceDistance = [[NSUserDefaults standardUserDefaults] floatForKey:@"MaxPlaceDistance"];
    }
    return self;
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    if (!_cursorIsActive || flags) {
        [self recalcCursorPosition];
    }
}

- (void)draw
{
    if (_cursorIsActive) {
        matrix_float4x4 translation = GSMatrixFromTranslation(_cursorPos + vector_make(0.5f, 0.5f, 0.5f));
        matrix_float4x4 modelView = matrix_multiply(translation, _camera.modelViewMatrix);
        matrix_float4x4 projection = _camera.projectionMatrix;
        
        matrix_float4x4 mvp = matrix_multiply(modelView, projection);
        [_cube drawWithModelViewProjectionMatrix:mvp];
    }
}

- (void)recalcCursorPosition
{
    vector_float3 rotated = quaternion_rotate_vector(_camera.cameraRot, vector_make(0, 0, -1));
    GSRay ray = GSRayMake(_camera.cameraEye, rotated);
    __block BOOL cursorIsActive = NO;
    __block vector_float3 prev = ray.origin;
    __block vector_float3 cursorPos;
    
    [_rayMarcher enumerateVoxelsOnRay:ray
                             maxDepth:_maxPlaceDistance
                            withBlock:^(vector_float3 p, BOOL *stop, BOOL *fail) {
                                GSVoxel voxel;
                                
                                if(![_chunkStore tryToGetVoxelAtPoint:p voxel:&voxel]) {
                                    *fail = YES; // Stops enumerations with un-successful condition
                                }
                                
                                if(voxel.type != VOXEL_TYPE_EMPTY) {
                                    cursorIsActive = YES;
                                    cursorPos = p;
                                    *stop = YES; // Stops enumeration with successful condition.
                                } else {
                                    prev = p;
                                }
                            }];
    
    _cursorIsActive = cursorIsActive;
    _cursorPos = cursorPos;
    _cursorPlacePos = prev;
}

@end
