//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSActiveRegion.h"
#import "GSFrustum.h"
#import "Voxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"
#import "GSGridItem.h"
#import "GSChunkVBOs.h"


@interface GSActiveRegion ()

- (void)updateVBOsInCameraFrustum;

@end


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    GLKVector3 _activeRegionExtent;

    /* List of GSChunkVBOs which are within the camera frustum. */
    NSArray *_vbosInCameraFrustum;

    /* This block may be invoked at any time to retrieve the GSChunkVBOs for any point in space. The block may return NULL if no
     * VBO has been generated for that point.
     */
    GSChunkVBOs * (^_vboProducer)(GLKVector3 p);

    /* Seconds until VBOs in the camera frustum are recalculated.
     * Note that these are always immediately recalculated when the camera moves.
     */
    float _timeUntilNextUpdate;

    /* Seconds between updates of VBOs in the camera frustum.
     * Note that these are always immediately recalculated when the camera moves.
     */
    float _updatePeriod;

    /* Dispatch queue for processing updates to _vbosInCameraFrustum. */
    dispatch_queue_t _updateQueue;
}

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                          camera:(GSCamera *)camera
                     vboProducer:(GSChunkVBOs * (^)(GLKVector3 p))vboProducer
{
    self = [super init];
    if (self) {
        assert(camera);
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _vbosInCameraFrustum = nil;
        _vboProducer = [vboProducer copy];
        _timeUntilNextUpdate = 0.0f;
        _updatePeriod = 1.0f;
        _updateQueue = dispatch_queue_create("GSActiveRegion._updateQueue", DISPATCH_QUEUE_SERIAL);

        [self updateWithDeltaTime:0.0f cameraModifiedFlags:(CAMERA_MOVED | CAMERA_TURNED)];
    }
    
    return self;
}

- (void)dealloc
{
    dispatch_release(_updateQueue);
}

- (void)draw
{
    NSArray *vbos = _vbosInCameraFrustum; // Reading the pointer is atomic.

    for(GSChunkVBOs *vbo in vbos)
    {
        [vbo draw];
    }
}

- (void)updateVBOsInCameraFrustum
{
    GSFrustum *frustum = _camera.frustum;
    NSMutableArray *vbosInCameraFrustum = [[NSMutableArray alloc] init];
    
    [self enumeratePointsWithBlock:^(GLKVector3 p) {
        GLKVector3 corners[8];
        
        corners[0] = MinCornerForChunkAtPoint(p);
        corners[1] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GLKVector3Add(corners[0], GLKVector3Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GLKVector3Add(corners[0], GLKVector3Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GLKVector3Add(corners[0], GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GLKVector3Add(corners[0], GLKVector3Make(0,            CHUNK_SIZE_Y, 0));
        
        if(GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:corners]) {
            GSChunkVBOs *vbo = _vboProducer(corners[0]);
            if(vbo) {
                [vbosInCameraFrustum addObject:vbo];
            }
        }
    }];
    
    /* Publish the list of chunk VBOs which are in the camera frustum.
     * This is consumed on the rendering thread by -draw. Assignment is atomic.
     */
    _vbosInCameraFrustum = vbosInCameraFrustum;
}

- (void)updateWithDeltaTime:(float)dt
        cameraModifiedFlags:(unsigned)flags;
{
    BOOL forceImmediateUpdate = (flags & CAMERA_TURNED) || (flags & CAMERA_MOVED);

    _timeUntilNextUpdate -= dt;
    if(forceImmediateUpdate || (_timeUntilNextUpdate<0.0f)) {
        _timeUntilNextUpdate = _updatePeriod;

        dispatch_async(_updateQueue, ^{
            [self updateVBOsInCameraFrustum];
        });
    }
}

- (void)enumeratePointsWithBlock:(void (^)(GLKVector3 p))block
{
    const GLKVector3 center = _camera.cameraEye;
    const ssize_t activeRegionExtentX = _activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = _activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = _activeRegionExtent.y/CHUNK_SIZE_Y;
    
    GSIntegerVector3 p, minP, maxP;
    
    minP = GSIntegerVector3_Make(-activeRegionExtentX, 0, -activeRegionExtentZ);
    maxP = GSIntegerVector3_Make(activeRegionExtentX, activeRegionSizeY, activeRegionExtentZ);
    
    FOR_BOX(p, minP, maxP)
    {
        assert((p.x+activeRegionExtentX) >= 0);
        assert(p.x < activeRegionExtentX);
        assert((p.z+activeRegionExtentZ) >= 0);
        assert(p.z < activeRegionExtentZ);
        assert(p.y >= 0);
        assert(p.y < activeRegionSizeY);
        
        GLKVector3 p1 = GLKVector3Make(center.x + p.x*CHUNK_SIZE_X, p.y*CHUNK_SIZE_Y, center.z + p.z*CHUNK_SIZE_Z);
        
        GLKVector3 centerP = GLKVector3Make(floorf(p1.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                                            floorf(p1.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                                            floorf(p1.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
        
        block(centerP);
    }
}

- (void)notifyOfChangeInActiveRegionVBOs
{
    dispatch_async(_updateQueue, ^{
        [self updateVBOsInCameraFrustum];
    });
}

@end
