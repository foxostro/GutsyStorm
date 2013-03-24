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


@implementation GSActiveRegion
{
    /* The camera at the center of the active region. */
    GSCamera *_camera;

    /* Vector specifies the AABB of the active region.
     * The camera position plus/minus this vector equals the max/min corners of the AABB.
     */
    GLKVector3 _activeRegionExtent;

    /* List of points corresponding to chunk AABBs which are within the camera frustum. */
    NSArray *_chunksInCameraFrustum;

    /* This block may be invoked at any time to retrieve the GSChunkVBO for any point in space. The block may return NULL if no
     * VBO has been generated for that point.
     */
    GSChunkVBOs * (^_vboProducer)(GLKVector3 p);

    /* This block may be invoked at any time to notify the VBO source of the active region's intentions to retrieve the
     * corresponding GSChunkVBO for that point sometime soon. The VBO source (the details of which are unimportant to this class)
     * may decide to act on this information by beginning VBO generation now.
     */
    void (^_vboPrefetcher)(GLKVector3 p);

    /* Keep track of chunks we've seen. Maps GSBoxedVector -> GSChunkVBOs.
     * This is necessary because _vboProducer may return nil for resident chunks when doing otherwise would end up blocking.
     * Each time _vboProducer produces a non-nil result, the chunk is stored in this dictionary.
     * Each time _vboProducer produces a nil result, we look for the corresponding chunk in this dictionary.
     */
    NSMutableDictionary *_rememberVBOs;
}

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
                          camera:(GSCamera *)camera
                     vboProducer:(GSChunkVBOs * (^)(GLKVector3 p))vboProducer
                   vboPrefetcher:(void (^)(GLKVector3 p))vboPrefetcher
{
    self = [super init];
    if (self) {
        assert(camera);
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

        _camera = camera;
        _activeRegionExtent = activeRegionExtent;
        _chunksInCameraFrustum = nil;
        _rememberVBOs = [[NSMutableDictionary alloc] init];
        _vboProducer = [vboProducer copy];
        _vboPrefetcher = [vboPrefetcher copy];

        [self updateWithCameraModifiedFlags:(CAMERA_MOVED | CAMERA_TURNED)];
    }
    
    return self;
}

- (void)draw
{
    NSArray *chunksInCameraFrustum = _chunksInCameraFrustum; // reading the pointer should be atomic here

    for(GSBoxedVector *boxed in chunksInCameraFrustum)
    {
        const GLKVector3 p = [boxed vectorValue];

        _vboPrefetcher(p);

        GSChunkVBOs *vbo = _vboProducer(p);

        /*if(vbo) {
            [_rememberVBOs setObject:vbo forKey:boxed];
        } else {
            vbo = [_rememberVBOs objectForKey:boxed];
        }*/

        [vbo draw];
    }
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    if(!(flags & CAMERA_TURNED) && !(flags & CAMERA_MOVED)) {
        return;
    }

    GSFrustum *frustum = _camera.frustum;
    NSMutableArray *chunksInCameraFrustum = [[NSMutableArray alloc] init];

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
            [chunksInCameraFrustum addObject:[GSBoxedVector boxedVectorWithVector:corners[0]]];
        }
    }];

    _chunksInCameraFrustum = chunksInCameraFrustum; // assignment should be atomic here
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

@end
