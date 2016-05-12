//
//  GSTerrainCursor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainCursor.h"
#import "GSCamera.h"
#import "GSTerrainChunkStore.h"
#import "GSTerrainRayMarcher.h"
#import "GSCube.h"
#import "GSMatrixUtils.h"
#import "GSGrid.h"
#import "GSGridSlot.h"
#import "GSVectorUtils.h"


@implementation GSTerrainCursor
{
    GSTerrainChunkStore *_chunkStore;
    GSCamera *_camera;
    GSTerrainRayMarcher *_rayMarcher;
    GSCube *_cube;
    float _maxPlaceDistance;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
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
        _rayMarcher = [[GSTerrainRayMarcher alloc] initWithChunkStore:chunkStore];
        _cursorIsActive = NO;
        _cursorPos = (vector_float3){0, 0, 0};
        _cursorPlacePos = (vector_float3){0, 0, 0};
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
                                
                                if(![self _tryToGetVoxel:&voxel atPoint:p]) {
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

- (BOOL)_tryToGetChunkVoxels:(GSChunkVoxelData * _Nonnull * _Nonnull)chunk atPoint:(vector_float3)p
{
    NSParameterAssert(p.y >= 0 && p.y < GSChunkSizeIntVec3.y);
    NSParameterAssert(chunk);
    
    GSGrid *gridVoxelData = _chunkStore.gridVoxelData;
    
    GSGridSlot *slot = [gridVoxelData slotAtPoint:p blocking:NO];
    
    if (!slot) {
        return NO;
    }
    
    if(![slot.lock tryLockForReading]) {
        return NO;
    }
    
    GSChunkVoxelData *voxels = (GSChunkVoxelData *)slot.item;
    if (voxels) {
        *chunk = voxels;
    }
    
    [slot.lock unlockForReading];
    
    return (voxels != nil);
}

- (BOOL)_tryToGetVoxel:(nonnull GSVoxel *)voxel atPoint:(vector_float3)pos
{
    NSParameterAssert(voxel);
    
    GSChunkVoxelData *chunk = nil;
    
    if(![self _tryToGetChunkVoxels:&chunk atPoint:pos]) {
        return NO;
    }
    
    assert(chunk);
    
    *voxel = [chunk voxelAtLocalPosition:GSMakeIntegerVector3(pos.x-chunk.minP.x,
                                                              pos.y-chunk.minP.y,
                                                              pos.z-chunk.minP.z)];
    
    return YES;
}

@end
