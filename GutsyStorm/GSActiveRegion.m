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
#import "GSGridVBOs.h"
#import "GLKVector3Extra.h"


static NSInteger sort(GSBoxedVector *p1, GSBoxedVector *p2, void *context)
{
    GSCamera *camera = (__bridge GSCamera *)context;
    GLKVector3 cameraEye = camera.cameraEye;
    float dist1 = GLKVector3Distance(cameraEye, [p1 vectorValue]);
    float dist2 = GLKVector3Distance(cameraEye, [p2 vectorValue]);
    
    if(dist1 < dist2) {
        return NSOrderedAscending;
    } else if(dist1 > dist2) {
        return NSOrderedDescending;
    } else {
        return NSOrderedSame;
    }
}


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    GLKVector3 _activeRegionExtent;
    
    /* Lock to protect _vbosInCameraFrustum */
    NSLock *_lockVBOsInCameraFrustum;

    /* GSChunkVBOs which are within the camera frustum. The dictionary maps chunk minP to the chunk. */
    NSDictionary *_vbosInCameraFrustum;
    
    GSGridVBOs *_gridVBOs;
}

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                          camera:(GSCamera *)camera
                        gridVBOs:(GSGridVBOs * )gridVBOs
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
        _lockVBOsInCameraFrustum = [[NSLock alloc] init];
        _gridVBOs = gridVBOs;

        [self update];
    }
    
    return self;
}

- (void)draw
{
    [_lockVBOsInCameraFrustum lock];
    NSDictionary *vbos = [_vbosInCameraFrustum copy];
    [_lockVBOsInCameraFrustum unlock];

    for(GSChunkVBOs *vbo in [vbos allValues])
    {
        [vbo draw];
    }
}

- (void)update
{
    GSFrustum *frustum = _camera.frustum;
    
    NSMutableDictionary *vbosInCameraFrustum = [NSMutableDictionary alloc];
    [_lockVBOsInCameraFrustum lock];
    if(_vbosInCameraFrustum) {
        vbosInCameraFrustum = [vbosInCameraFrustum initWithDictionary:_vbosInCameraFrustum];
        [_lockVBOsInCameraFrustum unlock];
    } else {
        [_lockVBOsInCameraFrustum unlock];
        vbosInCameraFrustum = [vbosInCameraFrustum init];
    }
    
    NSMutableArray *chunkPositions = [[NSMutableArray alloc] init];
    
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
            [chunkPositions addObject:[GSBoxedVector boxedVectorWithVector:corners[0]]];
        }
    }];
    
    [chunkPositions sortUsingFunction:sort context:(__bridge void *)(_camera)];
    
    for(GSBoxedVector *b in chunkPositions)
    {
        GSChunkVBOs *vbo = nil;
        
        [_gridVBOs objectAtPoint:[b vectorValue]
                        blocking:NO
                          object:&vbo
                 createIfMissing:YES
                allowAsyncCreate:YES];
        
        if(vbo) {
            NSNumber *key = [NSNumber numberWithUnsignedLongLong:GLKVector3Hash(vbo.minP)];
            [vbosInCameraFrustum setObject:vbo forKey:key];
        }
    };
    
    /* Publish the list of chunk VBOs which are in the camera frustum.
     * This is consumed on the rendering thread by -draw.
     */
    [_lockVBOsInCameraFrustum lock];
    _vbosInCameraFrustum = vbosInCameraFrustum;
    [_lockVBOsInCameraFrustum unlock];
}

- (void)enumeratePointsWithBlock:(void (^)(GLKVector3 p))block
{
    const GLKVector3 center = _camera.cameraEye;
    const ssize_t activeRegionExtentX = _activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = _activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionExtentY = _activeRegionExtent.y/CHUNK_SIZE_Y;
    
    GSIntegerVector3 p, minP, maxP;
    
    minP = GSIntegerVector3_Make(-activeRegionExtentX, -activeRegionExtentY, -activeRegionExtentZ);
    maxP = GSIntegerVector3_Make(activeRegionExtentX, activeRegionExtentY, activeRegionExtentZ);
    
    FOR_BOX(p, minP, maxP)
    {
        assert((p.x+activeRegionExtentX) >= 0);
        assert(p.x < activeRegionExtentX);
        assert((p.z+activeRegionExtentZ) >= 0);
        assert(p.z < activeRegionExtentZ);
        assert((p.y+activeRegionExtentY) >= 0);
        assert(p.y < activeRegionExtentY);
        
        GLKVector3 p1 = GLKVector3Make(center.x + p.x*CHUNK_SIZE_X, center.y + p.y*CHUNK_SIZE_Y, center.z + p.z*CHUNK_SIZE_Z);
        
        GLKVector3 centerP = GLKVector3Make(floorf(p1.x / CHUNK_SIZE_X) * CHUNK_SIZE_X + CHUNK_SIZE_X/2,
                                            floorf(p1.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y + CHUNK_SIZE_Y/2,
                                            floorf(p1.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z + CHUNK_SIZE_Z/2);
        
        block(centerP);
    }
}

- (void)purge
{
    [_lockVBOsInCameraFrustum lock];
    _vbosInCameraFrustum = nil;
    [_lockVBOsInCameraFrustum unlock];
}

@end
