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

@synthesize activeRegionExtent;
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
    }
    
    return self;
}


- (void)dealloc
{
    [self removeAllActiveChunks];
    free(activeChunks);
    
    [super dealloc];
}


- (void)forEachChunkDoBlock:(void (^)(GSChunkGeometryData *))block
{
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        block(activeChunks[i]);
    }
}


- (void)removeAllActiveChunks
{
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        [activeChunks[i] release];
        activeChunks[i] = nil;
    }
}


- (void)setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx
{
    assert(chunk);
    assert(idx < maxActiveChunks);
    
    [chunk retain];
    activeChunks[idx] = chunk;
}

@end
