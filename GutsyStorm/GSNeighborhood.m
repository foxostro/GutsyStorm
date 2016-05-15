//
//  GSNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSNeighborhood.h"
#import "GSVectorUtils.h"


@implementation GSNeighborhood
{
    NSObject *_neighbors[CHUNK_NUM_NEIGHBORS];
}

+ (vector_float3)offsetForNeighborIndex:(GSVoxelNeighborIndex)idx
{
    switch(idx)
    {
        case CHUNK_NEIGHBOR_POS_X_NEG_Z:
            return vector_make(+CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_POS_X_ZER_Z:
            return vector_make(+CHUNK_SIZE_X, 0, 0);
            
        case CHUNK_NEIGHBOR_POS_X_POS_Z:
            return vector_make(+CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_NEG_X_NEG_Z:
            return vector_make(-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_NEG_X_ZER_Z:
            return vector_make(-CHUNK_SIZE_X, 0, 0);
            
        case CHUNK_NEIGHBOR_NEG_X_POS_Z:
            return vector_make(-CHUNK_SIZE_X, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_ZER_X_NEG_Z:
            return vector_make(0, 0, -CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_ZER_X_POS_Z:
            return vector_make(0, 0, +CHUNK_SIZE_Z);
            
        case CHUNK_NEIGHBOR_CENTER:
            return vector_make(0, 0, 0);
            
        case CHUNK_NUM_NEIGHBORS:
            [NSException raise:NSInvalidArgumentException format:@"\"idx\" must not be CHUNK_NUM_NEIGHBORS."];
    }
    
    NSAssert(NO, @"shouldn't get here");
    return vector_make(0, 0, 0);
}

- (nonnull instancetype)init
{
    self = [super init];
    if (self) {
        for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            _neighbors[i] = nil;
        }
    }
    
    return self;
}

- (void)dealloc
{
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        _neighbors[i] = nil;
    }
}

- (nonnull NSObject *)neighborAtIndex:(GSVoxelNeighborIndex)idx
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    return _neighbors[idx];
}

- (void)setNeighborAtIndex:(GSVoxelNeighborIndex)idx neighbor:(nonnull NSObject *)neighbor
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    _neighbors[idx] = neighbor;
}

- (nonnull instancetype)copyReplacing:(nonnull NSObject *)original withNeighbor:(nonnull NSObject *)replacement
{
    NSParameterAssert(original && replacement);

    GSNeighborhood *theCopy = [[[self class] alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        NSObject *neighbor = [self neighborAtIndex:i];
        
        if (neighbor == original) {
            neighbor = replacement;
        }

        [theCopy setNeighborAtIndex:i neighbor:neighbor];
    }

    return theCopy;
}

@end
