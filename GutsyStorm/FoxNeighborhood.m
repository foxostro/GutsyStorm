//
//  FoxNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxIntegerVector3.h"
#import "FoxTerrainBuffer.h" // for terrain_buffer_element_t, needed by Voxel.h
#import "GSVoxel.h"
#import "FoxRay.h"
#import "FoxNeighborhood.h"
#import "FoxChunkVoxelData.h"
#import "FoxChunkStore.h"


@implementation FoxNeighborhood
{
    FoxChunkVoxelData *_neighbors[CHUNK_NUM_NEIGHBORS];
}

+ (vector_float3)offsetForNeighborIndex:(neighbor_index_t)idx
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

- (instancetype)init
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
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        _neighbors[i] = nil;
    }
}

- (FoxChunkVoxelData *)neighborAtIndex:(neighbor_index_t)idx
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    return _neighbors[idx];
}

- (void)setNeighborAtIndex:(neighbor_index_t)idx neighbor:(FoxChunkVoxelData *)neighbor
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    _neighbors[idx] = neighbor;
}

- (void)enumerateNeighborsWithBlock:(void (^)(FoxChunkVoxelData*))block
{
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        block(_neighbors[i]);
    }
}

- (void)enumerateNeighborsWithBlock2:(void (^)(neighbor_index_t, FoxChunkVoxelData*))block
{
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        block(i, _neighbors[i]);
    }
}

- (voxel_t *)newVoxelBufferFromNeighborhood
{
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    _Static_assert(sizeof(voxel_t) == sizeof(terrain_buffer_element_t), "expected to be able to store a voxel_t in a terrain_buffer_element_t");
    static const size_t count = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    voxel_t *combinedVoxelData = calloc(count, sizeof(voxel_t));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
    }

    [self enumerateNeighborsWithBlock2:^(neighbor_index_t i, FoxChunkVoxelData *voxels) {
        [voxels.voxels copyToCombinedNeighborhoodBuffer:(terrain_buffer_element_t *)combinedVoxelData
                                                  count:count
                                               neighbor:i];
    }];

    return combinedVoxelData;
}

- (FoxChunkVoxelData *)neighborVoxelAtPoint:(vector_long3 *)chunkLocalP
{
    if(chunkLocalP->x >= CHUNK_SIZE_X) {
        chunkLocalP->x -= CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_POS_X_ZER_Z];
        }
    } else if(chunkLocalP->x < 0) {
        chunkLocalP->x += CHUNK_SIZE_X;
        
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_NEG_X_ZER_Z];
        }
    } else {
        if(chunkLocalP->z < 0) {
            chunkLocalP->z += CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_ZER_X_NEG_Z];
        } else if(chunkLocalP->z >= CHUNK_SIZE_Z) {
            chunkLocalP->z -= CHUNK_SIZE_Z;
            return [self neighborAtIndex:CHUNK_NEIGHBOR_ZER_X_POS_Z];
        } else {
            return [self neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
        }
    }
}

- (voxel_t)voxelAtPoint:(vector_long3)p
{
    /* NOTE:
     *   - The voxels used for above/below the world must be updated when voxel def changes
     *   - Assumes each chunk spans the entire vertical extent of the world.
     */
    
    if(p.y < 0) {
        // Space below the world is always made of solid cubes.
        return (voxel_t){.outside=NO,
                         .exposedToAirOnTop=NO,
                         .opaque=YES,
                         .upsideDown=NO,
                         .dir=VOXEL_DIR_NORTH,
                         .type=VOXEL_TYPE_CUBE,
                         .tex=VOXEL_TEX_DIRT};
    } else if(p.y >= CHUNK_SIZE_Y) {
        // Space above the world is always empty.
        return (voxel_t){.outside=YES,
                         .exposedToAirOnTop=YES,
                         .opaque=NO,
                         .upsideDown=NO,
                         .dir=VOXEL_DIR_NORTH,
                         .type=VOXEL_TYPE_EMPTY,
                         .tex=0};
    } else {
        return [[self neighborVoxelAtPoint:&p] voxelAtLocalPosition:p];
    }
}

- (unsigned)lightAtPoint:(vector_long3)p getter:(FoxTerrainBuffer* (^)(FoxChunkVoxelData *c))getter
{
    assert(CHUNK_LIGHTING_MAX < (1ull << (sizeof(unsigned)*8)) && "unsigned int must be large enough to store light values");
    
    // Assumes each chunk spans the entire vertical extent of the world.
    
    if(p.y < 0) {
        return 0; // Space below the world is always dark.
    }
    
    if(p.y >= CHUNK_SIZE_Y) {
        return CHUNK_LIGHTING_MAX; // Space above the world is always bright.
    }
    
    FoxChunkVoxelData *chunk = [self neighborVoxelAtPoint:&p];
    FoxTerrainBuffer *lightingBuffer = getter(chunk);
    
    unsigned lightLevel = (unsigned)[lightingBuffer valueAtPosition:p];

    assert(lightLevel >= 0 && lightLevel <= CHUNK_LIGHTING_MAX);
    
    return lightLevel;
}

@end
