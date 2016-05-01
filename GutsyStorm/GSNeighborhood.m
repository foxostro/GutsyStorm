//
//  GSNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSTerrainBuffer.h" // for GSTerrainBufferElement, needed by Voxel.h
#import "GSVoxel.h"
#import "GSRay.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSTerrainChunkStore.h"


@implementation GSNeighborhood
{
    GSChunkVoxelData *_neighbors[CHUNK_NUM_NEIGHBORS];
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

- (nonnull GSChunkVoxelData *)neighborAtIndex:(GSVoxelNeighborIndex)idx
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    return _neighbors[idx];
}

- (void)setNeighborAtIndex:(GSVoxelNeighborIndex)idx neighbor:(nonnull GSChunkVoxelData *)neighbor
{
    NSAssert(idx < CHUNK_NUM_NEIGHBORS, @"idx is out of range");
    _neighbors[idx] = neighbor;
}

- (void)enumerateNeighborsWithBlock:(void (^ _Nonnull)(GSChunkVoxelData * _Nonnull))block
{
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        block(_neighbors[i]);
    }
}

- (void)enumerateNeighborsWithBlock2:(void (^ _Nonnull)(GSVoxelNeighborIndex, GSChunkVoxelData * _Nonnull))block
{
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        block(i, _neighbors[i]);
    }
}

- (nonnull GSVoxel *)newVoxelBufferFromNeighborhood
{
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    _Static_assert(sizeof(GSVoxel) == sizeof(GSTerrainBufferElement), "expected to be able to store a GSVoxel in a GSTerrainBufferElement");
    static const size_t count = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    GSVoxel *combinedVoxelData = calloc(count, sizeof(GSVoxel));
    if(!combinedVoxelData) {
        [NSException raise:NSMallocException format:@"Failed to allocate memory for combinedVoxelData."];
    }

    [self enumerateNeighborsWithBlock2:^(GSVoxelNeighborIndex i, GSChunkVoxelData *voxels) {
        [voxels.voxels copyToCombinedNeighborhoodBuffer:(GSTerrainBufferElement *)combinedVoxelData
                                                  count:count
                                               neighbor:i];
    }];

    return combinedVoxelData;
}

- (nonnull GSChunkVoxelData *)neighborVoxelAtPoint:(nonnull vector_long3 *)chunkLocalP
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

- (GSVoxel)voxelAtPoint:(vector_long3)p
{
    /* NOTE:
     *   - The voxels used for above/below the world must be updated when voxel def changes
     *   - Assumes each chunk spans the entire vertical extent of the world.
     */
    
    if(p.y < 0) {
        // Space below the world is always made of solid cubes.
        return (GSVoxel){.outside=NO,
                         .exposedToAirOnTop=NO,
                         .opaque=YES,
                         .upsideDown=NO,
                         .dir=VOXEL_DIR_NORTH,
                         .type=VOXEL_TYPE_CUBE,
                         .tex=VOXEL_TEX_DIRT};
    } else if(p.y >= CHUNK_SIZE_Y) {
        // Space above the world is always empty.
        return (GSVoxel){.outside=YES,
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

- (unsigned)lightAtPoint:(vector_long3)p
                  getter:(GSTerrainBuffer * _Nonnull (^ _Nonnull)(GSChunkVoxelData * _Nonnull c))getter
{
    assert(CHUNK_LIGHTING_MAX < (1ull << (sizeof(unsigned)*8)) &&
           "unsigned int must be large enough to store light values");
    
    // Assumes each chunk spans the entire vertical extent of the world.
    
    if(p.y < 0) {
        return 0; // Space below the world is always dark.
    }
    
    if(p.y >= CHUNK_SIZE_Y) {
        return CHUNK_LIGHTING_MAX; // Space above the world is always bright.
    }
    
    GSChunkVoxelData *chunk = [self neighborVoxelAtPoint:&p];
    GSTerrainBuffer *lightingBuffer = getter(chunk);
    
    unsigned lightLevel = (unsigned)[lightingBuffer valueAtPosition:p];

    assert(lightLevel >= 0 && lightLevel <= CHUNK_LIGHTING_MAX);
    
    return lightLevel;
}

- (nonnull instancetype)copyReplacing:(nonnull GSChunkVoxelData *)voxels1
                         withNeighbor:(nonnull GSChunkVoxelData *)voxels2
{
    NSParameterAssert(voxels1 && voxels2);

    GSNeighborhood *theCopy = [[GSNeighborhood alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSChunkVoxelData *voxels = [self neighborAtIndex:i];
        
        if (voxels == voxels1) {
            voxels = voxels2;
        }

        [theCopy setNeighborAtIndex:i neighbor:voxels];
    }

    return theCopy;
}

@end
