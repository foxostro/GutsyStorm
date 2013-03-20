//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GLKVector3Extra.h"
#import "GSIntegerVector3.h"
#import "GSActiveRegion.h"
#import "GSFrustum.h"
#import "GSIntegerVector3.h"
#import "GSBuffer.h"
#import "Voxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"
#import "GSGridItem.h"
#import "GSChunkVBOs.h"


@interface GSActiveRegion ()

- (void)unsafelyEnumerateActiveChunkWithBlock:(void (^)(GSChunkVBOs *))block;
- (void)removeAllActiveChunks;
- (void)setActiveChunk:(GSChunkVBOs *)chunk atIndex:(NSUInteger)idx;

@end


@implementation GSActiveRegion
{
    GLKVector3 _activeRegionExtent; // The active region is specified relative to the camera position.
    GSChunkVBOs * __strong *_activeChunks;
    NSLock *_lock;
    NSUInteger _oldCenterChunkID; // FIXME: chunks are identified by hashes, but the hashes are not unique
    NSMutableArray *retainChunkTemporarily;
}

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
{
    self = [super init];
    if (self) {
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);

        _oldCenterChunkID = GLKVector3Hash(MinCornerForChunkAtPoint2(INFINITY, 0, INFINITY));

        _activeRegionExtent = activeRegionExtent;
        
        _maxActiveChunks = (2*_activeRegionExtent.x/CHUNK_SIZE_X)
                         * (_activeRegionExtent.y/CHUNK_SIZE_Y)
                         * (2*_activeRegionExtent.z/CHUNK_SIZE_Z);

        retainChunkTemporarily = [[NSMutableArray alloc] initWithCapacity:_maxActiveChunks];

        _activeChunks = (GSChunkVBOs * __strong *)calloc(_maxActiveChunks, sizeof(GSChunkGeometryData *));
        
        if(!_activeChunks) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating activeChunk."];
        }
        
        _lock = [[NSLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [self removeAllActiveChunks];
    free(_activeChunks);
}

- (void)unsafelyEnumerateActiveChunkWithBlock:(void (^)(GSChunkVBOs *))block
{
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        GSChunkVBOs *chunk = _activeChunks[i];
        if(chunk) {
            block(chunk);
        }
    }
}

- (void)draw
{
    // FIXME: need a new grid for VBO data. These items are drawn if present in the grid.
    [_lock lock];
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        GSChunkVBOs *vbo = _activeChunks[i];
        [vbo draw];
    }
    [_lock unlock];
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
                               camera:(GSCamera *)camera
                        chunkProducer:(GSChunkVBOs * (^)(GLKVector3 p))chunkProducer
{
    if(!(flags & CAMERA_TURNED) && !(flags & CAMERA_MOVED)) {
        return;
    }

    [_lock lock];
    
    // If the camera moved then recalculate the set of active chunks.
    if(flags & CAMERA_MOVED) {
        // We can avoid a lot of work if the camera hasn't moved enough to add/remove any chunks in the active region.
        NSUInteger newCenterChunkID = GLKVector3Hash(MinCornerForChunkAtPoint(camera.cameraEye));

        if(_oldCenterChunkID != newCenterChunkID) {
            _oldCenterChunkID = newCenterChunkID;

            [self unsafelyEnumerateActiveChunkWithBlock:^(GSChunkVBOs *vbo) {
                [retainChunkTemporarily addObject:vbo];
            }];
    
            [self removeAllActiveChunks];
    
            __block NSUInteger i = 0;
            [self enumeratePointsInActiveRegionNearCamera:camera usingBlock:^(GLKVector3 p) {
                [self setActiveChunk:chunkProducer(p) atIndex:i];
                i++;
            }];
            assert(i == _maxActiveChunks);
            
            [retainChunkTemporarily removeAllObjects];
        }
    }

#if 0
    // FIXME: need a new way to track chunk visibility. GSChunkGeometry and GSChunkVBO are going to be immutable objects.
    GSFrustum *frustum = camera.frustum;
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        if(_activeChunks[i]) {
            _activeChunks[i].visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:_activeChunks[i].corners]);
        }
    }
#endif

    [_lock unlock];
}

- (void)enumerateActiveChunkWithBlock:(void (^)(GSChunkVBOs *))block
{
    // Copy active region blocks so we don't have to hold the lock while running the block over and over again.
    GSChunkVBOs * __strong *temp = (GSChunkVBOs * __strong *)calloc(_maxActiveChunks, sizeof(GSChunkVBOs *));
    if(!temp) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating temp buffer."];
    }
    
    [_lock lock];
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        temp[i] = _activeChunks[i];
    }
    [_lock unlock];
    
    [self unsafelyEnumerateActiveChunkWithBlock:block];
    
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        temp[i] = nil; // explicitly drop the reference for ARC
    }
    free(temp);
}

- (void)removeAllActiveChunks
{
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        _activeChunks[i] = nil;
    }
}

- (void)setActiveChunk:(GSChunkVBOs *)chunk atIndex:(NSUInteger)idx
{
    assert(chunk);
    assert(idx < _maxActiveChunks);
    
    _activeChunks[idx] = chunk;
}

- (NSArray *)chunksListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedChunks
{
    GLKVector3 cameraEye = [camera cameraEye];
    
    NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(NSObject <GSGridItem> *a, NSObject <GSGridItem> *b) {
        static const GLKVector3 halfSize = {CHUNK_SIZE_X / 2, CHUNK_SIZE_Y / 2, CHUNK_SIZE_Z / 2};
        GLKVector3 centerA = GLKVector3Add(a.minP, halfSize);
        GLKVector3 centerB = GLKVector3Add(b.minP, halfSize);
        float distA = GLKVector3Length(GLKVector3Subtract(centerA, cameraEye));
        float distB = GLKVector3Length(GLKVector3Subtract(centerB, cameraEye));
        return [@(distA) compare:@(distB)];
    }];
    
    return sortedChunks;
}

- (NSArray *)pointsListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedPoints
{
    GLKVector3 center = [camera cameraEye];
    
    return [unsortedPoints sortedArrayUsingComparator: ^(id a, id b) {
        GLKVector3 centerA = [(GSBoxedVector *)a vectorValue];
        GLKVector3 centerB = [(GSBoxedVector *)b vectorValue];
        float distA = GLKVector3Length(GLKVector3Subtract(centerA, center));
        float distB = GLKVector3Length(GLKVector3Subtract(centerB, center));
        return [@(distA) compare:@(distB)];
    }];
}

- (void)enumeratePointsInActiveRegionNearCamera:(GSCamera *)camera usingBlock:(void (^)(GLKVector3))myBlock
{
    const GLKVector3 center = [camera cameraEye];
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
        
        myBlock(centerP);
    }
}

@end
