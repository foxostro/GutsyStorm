//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSActiveRegion.h"
#import "Voxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"

@interface GSActiveRegion ()

- (void)unsafelyEnumerateActiveChunkWithBlock:(void (^)(GSChunkGeometryData *))block;
- (void)removeAllActiveChunks;
- (void)setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx;

@end


@implementation GSActiveRegion
{
    GLKVector3 _activeRegionExtent; // The active region is specified relative to the camera position.
    GSChunkGeometryData * __strong *_activeChunks;
    NSLock *_lock;
}

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent
{
    self = [super init];
    if (self) {
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);
        
        _activeRegionExtent = activeRegionExtent;
        
        _maxActiveChunks = (2*_activeRegionExtent.x/CHUNK_SIZE_X)
                         * (_activeRegionExtent.y/CHUNK_SIZE_Y)
                         * (2*_activeRegionExtent.z/CHUNK_SIZE_Z);
        
        _activeChunks = (GSChunkGeometryData * __strong *)calloc(_maxActiveChunks, sizeof(GSChunkGeometryData *));
        
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


- (void)unsafelyEnumerateActiveChunkWithBlock:(void (^)(GSChunkGeometryData *))block
{
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        GSChunkGeometryData *chunk = _activeChunks[i];
        if(chunk) {
            block(chunk);
        }
    }
}


- (void)enumerateActiveChunkWithBlock:(void (^)(GSChunkGeometryData *))block
{
    // Copy active region blocks so we don't have to hold the lock while running the block over and over again.
    GSChunkGeometryData * __strong *temp = (GSChunkGeometryData * __strong *)calloc(_maxActiveChunks,
                                                                                    sizeof(GSChunkGeometryData *));
    if(!temp) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating temp buffer."];
    }
    
    [_lock lock];
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        if(_activeChunks[i]) {
            temp[i] = _activeChunks[i];
        }
    }
    [_lock unlock];
    
    for(NSUInteger i = 0; i < _maxActiveChunks; ++i)
    {
        if(temp[i]) {
            block(temp[i]);
        }
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


- (void)setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx
{
    assert(chunk);
    assert(idx < _maxActiveChunks);
    
    _activeChunks[idx] = chunk;
}


- (NSArray *)chunksListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedChunks
{
    GLKVector3 cameraEye = [camera cameraEye];
    
    NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(id a, id b) {
        GSChunkData *chunkA = (GSChunkData *)a;
        GSChunkData *chunkB = (GSChunkData *)b;
        GLKVector3 centerA = GLKVector3MultiplyScalar(GLKVector3Add([chunkA minP], [chunkA maxP]), 0.5);
        GLKVector3 centerB = GLKVector3MultiplyScalar(GLKVector3Add([chunkB minP], [chunkB maxP]), 0.5);
        float distA = GLKVector3Length(GLKVector3Subtract(centerA, cameraEye));
        float distB = GLKVector3Length(GLKVector3Subtract(centerB, cameraEye));;
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
        
        GLKVector3 p2 = [GSChunkData centerPointOfChunkAtPoint:p1];
        
        myBlock(p2);
    }
}


- (void)updateWithSorting:(BOOL)sorted
                   camera:(GSCamera *)camera
            chunkProducer:(GSChunkGeometryData * (^)(GLKVector3 p))chunkProducer
{
    [_lock lock];
    NSMutableArray *retainChunkTemporarily = [[NSMutableArray alloc] initWithCapacity:_maxActiveChunks];
    [self unsafelyEnumerateActiveChunkWithBlock:^(GSChunkGeometryData *geometry) {
        [retainChunkTemporarily addObject:geometry];
    }];
    
    [self removeAllActiveChunks];
    
    if(sorted) {
        NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
        
        [self enumeratePointsInActiveRegionNearCamera:camera usingBlock:^(GLKVector3 p) {
            [unsortedChunks addObject:[GSBoxedVector boxedVectorWithVector:p]];
        }];
        
        // Sort by distance from the camera. Near chunks are first.
        NSArray *sortedChunks = [self pointsListSortedByDistFromCamera:camera unsortedList:unsortedChunks];
        
        // Fill the activeChunks array.
        NSUInteger i = 0;
        for(GSBoxedVector *b in sortedChunks)
        {
            [self setActiveChunk:chunkProducer([b vectorValue]) atIndex:i];
            i++;
        }
        assert(i == _maxActiveChunks);
        
    } else {
        __block NSUInteger i = 0;
        [self enumeratePointsInActiveRegionNearCamera:camera usingBlock:^(GLKVector3 p) {
            [self setActiveChunk:chunkProducer(p) atIndex:i];
            i++;
        }];
        assert(i == _maxActiveChunks);
    }
    
    [_lock unlock];
}

@end
