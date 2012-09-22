//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSActiveRegion.h"
#import "Voxel.h"

@implementation GSActiveRegion

@synthesize maxActiveChunks;

- (id)initWithActiveRegionExtent:(GSVector3)_activeRegionExtent
{
    self = [super init];
    if (self) {
        assert(fmodf(_activeRegionExtent.x, CHUNK_SIZE_X) == 0);
        assert(fmodf(_activeRegionExtent.y, CHUNK_SIZE_Y) == 0);
        assert(fmodf(_activeRegionExtent.z, CHUNK_SIZE_Z) == 0);
        
        activeRegionExtent = _activeRegionExtent;
        
        maxActiveChunks = (2*activeRegionExtent.x/CHUNK_SIZE_X)
                        * (activeRegionExtent.y/CHUNK_SIZE_Y)
                        * (2*activeRegionExtent.z/CHUNK_SIZE_Z);
        
        activeChunks = calloc(maxActiveChunks, sizeof(GSChunkGeometryData *));
        
        lock = [[NSLock alloc] init];
    }
    
    return self;
}


- (void)dealloc
{
    [self removeAllActiveChunks];
    free(activeChunks);
    [lock release];
    
    [super dealloc];
}


- (void)forEachChunkDoBlock:(void (^)(GSChunkGeometryData *))block
{
    [lock lock];
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        GSChunkGeometryData *chunk = activeChunks[i];
        assert(chunk);
        block(chunk);
    }
    [lock unlock];
}


- (void)removeAllActiveChunks
{
    [lock lock];
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        [activeChunks[i] release];
        activeChunks[i] = nil;
    }
    [lock unlock];
}


- (void)setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx
{
    assert(chunk);
    assert(idx < maxActiveChunks);
    
    [chunk retain];
    [lock lock];
    activeChunks[idx] = chunk;
    [lock unlock];
}

- (GSVector3)randomPointInActiveRegionWithCameraPos:(GSVector3)cameraEye
{
    GSVector3 randVec = activeRegionExtent;
    randVec.x *= 2.0 * ((float)rand()/RAND_MAX) - 1.0;
    randVec.z *= 2.0 * ((float)rand()/RAND_MAX) - 1.0;
    randVec.y = 0;
    GSVector3 p = GSVector3_Add(cameraEye, randVec);
    return p;
}

@end
