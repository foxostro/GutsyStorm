//
//  GSActiveRegion.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSActiveRegion.h"
#import "Voxel.h"
#import "GSBoxedVector.h"
#import "GSCamera.h"

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
        
        if(!activeChunks) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating activeChunk."];
        }
        
        lock = [[NSLock alloc] init];
    }
    
    return self;
}


- (void)dealloc
{
    [self _removeAllActiveChunks];
    free(activeChunks);
    [lock release];
    
    [super dealloc];
}


- (void)_enumerateActiveChunkWithBlock:(void (^)(GSChunkGeometryData *))block
{
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        GSChunkGeometryData *chunk = activeChunks[i];
        if(chunk) {
            block(chunk);
        }
    }
}


- (void)enumerateActiveChunkWithBlock:(void (^)(GSChunkGeometryData *))block
{
    const size_t len = maxActiveChunks * sizeof(GSChunkGeometryData *);
    
    // Copy active region blocks so we don't have to hold the lock while running the block over and over again.
    GSChunkGeometryData **temp = malloc(len);
    if(!temp) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating temp buffer."];
    }
    
    [lock lock];
    memcpy(temp, activeChunks, len);
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        if(temp[i]) {
            [temp[i] retain];
        }
    }
    [lock unlock];
    
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        if(temp[i]) {
            block(temp[i]);
            [temp[i] release];
        }
    }
    
    free(temp);
}


- (void)_removeAllActiveChunks
{
    for(NSUInteger i = 0; i < maxActiveChunks; ++i)
    {
        [activeChunks[i] release];
        activeChunks[i] = nil;
    }
}


- (void)_setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx
{
    assert(chunk);
    assert(idx < maxActiveChunks);
    
    [chunk retain];
    activeChunks[idx] = chunk;
}


- (NSArray *)chunksListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedChunks
{
    GSVector3 cameraEye = [camera cameraEye];
    
    NSArray *sortedChunks = [unsortedChunks sortedArrayUsingComparator: ^(id a, id b) {
        GSChunkData *chunkA = (GSChunkData *)a;
        GSChunkData *chunkB = (GSChunkData *)b;
        GSVector3 centerA = GSVector3_Scale(GSVector3_Add([chunkA minP], [chunkA maxP]), 0.5);
        GSVector3 centerB = GSVector3_Scale(GSVector3_Add([chunkB minP], [chunkB maxP]), 0.5);
        float distA = GSVector3_Length(GSVector3_Sub(centerA, cameraEye));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, cameraEye));;
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
    
    return sortedChunks;
}


- (NSArray *)pointsListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedPoints
{
    GSVector3 center = [camera cameraEye];
    
    return [unsortedPoints sortedArrayUsingComparator: ^(id a, id b) {
        GSVector3 centerA = [(GSBoxedVector *)a vectorValue];
        GSVector3 centerB = [(GSBoxedVector *)b vectorValue];
        float distA = GSVector3_Length(GSVector3_Sub(centerA, center));
        float distB = GSVector3_Length(GSVector3_Sub(centerB, center));
        return [[NSNumber numberWithFloat:distA] compare:[NSNumber numberWithFloat:distB]];
    }];
}


- (void)enumeratePointsInActiveRegionNearCamera:(GSCamera *)camera usingBlock:(void (^)(GSVector3))myBlock
{
    const GSVector3 center = [camera cameraEye];
    const ssize_t activeRegionExtentX = activeRegionExtent.x/CHUNK_SIZE_X;
    const ssize_t activeRegionExtentZ = activeRegionExtent.z/CHUNK_SIZE_Z;
    const ssize_t activeRegionSizeY = activeRegionExtent.y/CHUNK_SIZE_Y;
    
    for(ssize_t x = -activeRegionExtentX; x < activeRegionExtentX; ++x)
    {
        for(ssize_t y = 0; y < activeRegionSizeY; ++y)
        {
            for(ssize_t z = -activeRegionExtentZ; z < activeRegionExtentZ; ++z)
            {
                assert((x+activeRegionExtentX) >= 0);
                assert(x < activeRegionExtentX);
                assert((z+activeRegionExtentZ) >= 0);
                assert(z < activeRegionExtentZ);
                assert(y >= 0);
                assert(y < activeRegionSizeY);
                
                GSVector3 p1 = GSVector3_Make(center.x + x*CHUNK_SIZE_X, y*CHUNK_SIZE_Y, center.z + z*CHUNK_SIZE_Z);
                
                GSVector3 p2 = [GSChunkData centerPointOfChunkAtPoint:p1];
                
                myBlock(p2);
            }
        }
    }
}


- (void)updateWithSorting:(BOOL)sorted
                   camera:(GSCamera *)camera
            chunkProducer:(GSChunkGeometryData * (^)(GSVector3 p))chunkProducer
{
    [lock lock];
    NSMutableArray *retainChunkTemporarily = [[NSMutableArray alloc] initWithCapacity:maxActiveChunks];
    [self _enumerateActiveChunkWithBlock:^(GSChunkGeometryData *geometry) {
        [retainChunkTemporarily addObject:geometry];
    }];
    
    [self _removeAllActiveChunks];
    
    if(sorted) {
        NSMutableArray *unsortedChunks = [[NSMutableArray alloc] init];
        
        [self enumeratePointsInActiveRegionNearCamera:camera usingBlock:^(GSVector3 p) {
            [unsortedChunks addObject:[GSBoxedVector boxedVectorWithVector:p]];
        }];
        
        // Sort by distance from the camera. Near chunks are first.
        NSArray *sortedChunks = [self pointsListSortedByDistFromCamera:camera unsortedList:unsortedChunks];
        
        // Fill the activeChunks array.
        NSUInteger i = 0;
        for(GSBoxedVector *b in sortedChunks)
        {
            [self _setActiveChunk:chunkProducer([b vectorValue]) atIndex:i];
            i++;
        }
        assert(i == maxActiveChunks);
        
        [unsortedChunks release];
    } else {
        __block NSUInteger i = 0;
        [self enumeratePointsInActiveRegionNearCamera:camera usingBlock:^(GSVector3 p) {
            [self _setActiveChunk:chunkProducer(p) atIndex:i];
            i++;
        }];
        assert(i == maxActiveChunks);
    }
    
    [retainChunkTemporarily release];
    [lock unlock];
}

@end
