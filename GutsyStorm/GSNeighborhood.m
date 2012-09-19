//
//  GSGridNeighbors.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSNeighborhood.h"
#import "Voxel.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"


@implementation GSNeighborhood

+ (NSLock *)_sharedVoxelDataLock
{
    static dispatch_once_t onceToken;
    static NSLock *a = nil;
    
    dispatch_once(&onceToken, ^{
        a = [[NSLock alloc] init];
        [a setName:@"GSNeighborhood._sharedVoxelDataLock"];
    });
    
    return a;
}


+ (NSLock *)_sharedSkylightLock
{
    static dispatch_once_t onceToken;
    static NSLock *a = nil;
    
    dispatch_once(&onceToken, ^{
        a = [[NSLock alloc] init];
        [a setName:@"GSNeighborhood._sharedSunlightLock"];
    });
    
    return a;
}


+ (GSVector3)getOffsetForNeighborIndex:(neighbor_index_t)idx
{
    switch(idx)
    {
        case CHUNK_NEIGHBOR_POS_X_NEG_Z:
            return GSVector3_Make(+CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_POS_X_ZER_Z:
            return GSVector3_Make(+CHUNK_SIZE_X, 0, 0);
            
        case CHUNK_NEIGHBOR_POS_X_POS_Z:
            return GSVector3_Make(+CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_NEG_X_NEG_Z:
            return GSVector3_Make(-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_NEG_X_ZER_Z:
            return GSVector3_Make(-CHUNK_SIZE_X, 0, 0);
            
        case CHUNK_NEIGHBOR_NEG_X_POS_Z:
            return GSVector3_Make(-CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_ZER_X_NEG_Z:
            return GSVector3_Make(0, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_ZER_X_POS_Z:
            return GSVector3_Make(0, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_CENTER:
            return GSVector3_Make(0, 0, 0);
            
        case CHUNK_NUM_NEIGHBORS:
            [NSException raise:NSInvalidArgumentException format:@"\"idx\" must not be CHUNK_NUM_NEIGHBORS."];
    }
    
    NSAssert(NO, @"shouldn't get here");
    return GSVector3_Make(0, 0, 0);
}


- (id)init
{
    self = [super init];
    if (self) {
        for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            neighbors[i] = nil;
        }
    }
    
    return self;
}


- (void)dealloc
{
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [neighbors[i] release];
    }
    
    [super dealloc];
}


- (GSChunkVoxelData *)getNeighborAtIndex:(neighbor_index_t)idx
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    return neighbors[idx];
}


- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(GSChunkVoxelData *)neighbor
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    [neighbors[idx] release];
    neighbors[idx] = neighbor;
    [neighbors[idx] retain];
}


- (void)forEachNeighbor:(void (^)(GSChunkVoxelData*))block
{
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        block(neighbors[i]);
    }
}


- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    NSLock *globalLock = [GSNeighborhood _sharedVoxelDataLock];
    
    [globalLock lock];
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[neighbor getVoxelDataLock] lockForReading];
    }];
    [globalLock unlock];
    
    block();
    
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[neighbor getVoxelDataLock] unlockForReading];
    }];
}


- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    NSLock *globalLock = [GSNeighborhood _sharedVoxelDataLock];
    
    [globalLock lock];
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[neighbor getVoxelDataLock] lockForWriting];
    }];
    [globalLock unlock];
    
    block();
    
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[neighbor getVoxelDataLock] unlockForWriting];
    }];
}


- (void)readerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block
{
    NSLock *globalLock = [GSNeighborhood _sharedSkylightLock];
    
    [globalLock lock];
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[[neighbor performSelector:buffer] lockLightingBuffer] lockForReading];
    }];
    [globalLock unlock];
    
    block();
    
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[[neighbor performSelector:buffer] lockLightingBuffer] unlockForReading];
    }];
}


- (void)writerAccessToLightingBuffer:(SEL)buffer usingBlock:(void (^)(void))block
{
    NSLock *globalLock = [GSNeighborhood _sharedSkylightLock];
    
    [globalLock lock];
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[[neighbor performSelector:buffer] lockLightingBuffer] lockForWriting];
    }];
    [globalLock unlock];
    
    block();
    
    [self forEachNeighbor:^(GSChunkVoxelData *neighbor) {
        [[[neighbor performSelector:buffer] lockLightingBuffer] unlockForWriting];
    }];
}


- (GSChunkVoxelData *)getNeighborVoxelAtPoint:(GSIntegerVector3 *)chunkLocalP
{
    if(chunkLocalP->x >= CHUNK_SIZE_X) {
        chunkLocalP->x -= CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_POS_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_POS_X_POS_Z];
        } else {
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_POS_X_ZER_Z];
        }
    } else if(chunkLocalP->x < 0) {
        chunkLocalP->x += CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_NEG_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_NEG_X_POS_Z];
        } else {
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_NEG_X_ZER_Z];
        }
    } else {
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_ZER_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_ZER_X_POS_Z];
        } else {
            return [self getNeighborAtIndex:CHUNK_NEIGHBOR_CENTER];
        }
    }
}


- (BOOL)isEmptyAtPoint:(GSIntegerVector3)p
{
    // Assumes each chunk spans the entire vertical extent of the world.
    
    if(p.y < 0) {
        return NO; // Space below the world is always full.
    }
    
    if(p.y >= CHUNK_SIZE_Y) {
        return YES; // Space above the world is always empty.
    }
    
    return isVoxelEmpty([[self getNeighborVoxelAtPoint:&p] getVoxelAtPoint:p]);
}


- (uint8_t)lightAtPoint:(GSIntegerVector3)p buffer:(SEL)buffer
{
    // Assumes each chunk spans the entire vertical extent of the world.
    
    if(p.y < 0) {
        return 0; // Space below the world is always dark.
    }
    
    if(p.y >= CHUNK_SIZE_Y) {
        return CHUNK_LIGHTING_MAX; // Space above the world is always bright.
    }
    
    GSChunkVoxelData *chunk = [self getNeighborVoxelAtPoint:&p];
    
    uint8_t lightLevel = [[chunk performSelector:buffer] lightAtPoint:p];

    assert(lightLevel >= 0 && lightLevel <= CHUNK_LIGHTING_MAX);
    
    return lightLevel;
}

@end
