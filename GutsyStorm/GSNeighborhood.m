//
//  GSNeighborhood.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSIntegerVector3.h"
#import "GSBuffer.h" // for buffer_element_t, needed by Voxel.h
#import "Voxel.h"
#import "GSRay.h"
#import "GSNeighborhood.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"


@interface GSNeighborhood ()

- (void)clear;

@end


@implementation GSNeighborhood
{
    GSChunkVoxelData *_neighbors[3][3][3];
}

- (id)init
{
    self = [super init];
    if (self) {
        [self clear];
    }
    
    return self;
}

- (void)dealloc
{
    [self clear];
}

- (void)clear
{
    const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSIntegerVector3 p;
    FOR_BOX(p, a, b)
    {
        [self setNeighborAtPosition:p neighbor:nil];
    }
}

- (GSChunkVoxelData *)neighborAtPosition:(GSIntegerVector3)p
{
    assert(p.x >= -1 && p.x <= +1);
    assert(p.y >= -1 && p.y <= +1);
    assert(p.z >= -1 && p.z <= +1);
    return _neighbors[p.x+1][p.y+1][p.z+1];
}

- (void)setNeighborAtPosition:(GSIntegerVector3)p neighbor:(GSChunkVoxelData *)neighbor
{
    assert(p.x >= -1 && p.x <= +1);
    assert(p.y >= -1 && p.y <= +1);
    assert(p.z >= -1 && p.z <= +1);
    _neighbors[p.x+1][p.y+1][p.z+1] = neighbor;
}

- (void)enumerateNeighborsWithBlock:(void (^)(GSChunkVoxelData*))block
{
    const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSIntegerVector3 p;
    FOR_BOX(p, a, b)
    {
        block([self neighborAtPosition:p]);
    }
}

- (void)enumerateNeighborsWithBlock2:(void (^)(GSIntegerVector3 p, GSChunkVoxelData*))block
{
    const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSIntegerVector3 p;
    FOR_BOX(p, a, b)
    {
        block(p, [self neighborAtPosition:p]);
    }
}

- (voxel_t *)newVoxelBufferFromNeighborhood
{
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    _Static_assert(sizeof(voxel_t) == sizeof(buffer_element_t), "expected to be able to store a voxel_t in a buffer_element_t");
    static const size_t count = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    voxel_t *combinedVoxelData = calloc(count, sizeof(voxel_t));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
    }

    [self enumerateNeighborsWithBlock2:^(GSIntegerVector3 positionInNeighborhood, GSChunkVoxelData *voxels) {
        [voxels.voxels copyToCombinedNeighborhoodBuffer:(buffer_element_t *)combinedVoxelData
                                                  count:count
                                 positionInNeighborhood:positionInNeighborhood];
    }];

    return combinedVoxelData;
}

- (GSChunkVoxelData *)neighborVoxelAtPoint:(GSIntegerVector3 *)outChunkLocalPos
{
    assert(outChunkLocalPos);

    GSIntegerVector3 p = *outChunkLocalPos;
    GSIntegerVector3 neighbor = ivecZero;

    if(p.x < 0) {
        p.x += CHUNK_SIZE_X;
        neighbor.x = -1;
    } else if(p.x >= CHUNK_SIZE_X) {
        p.x -= CHUNK_SIZE_X;
        neighbor.x = +1;
    } else {
        neighbor.x = 0;
    }

    if(p.y < 0) {
        p.y += CHUNK_SIZE_Y;
        neighbor.y = -1;
    } else if(p.y >= CHUNK_SIZE_Y) {
        p.y -= CHUNK_SIZE_Y;
        neighbor.y = +1;
    } else {
        neighbor.y = 0;
    }

    if(p.z < 0) {
        p.z += CHUNK_SIZE_Z;
        neighbor.z = -1;
    } else if(p.z >= CHUNK_SIZE_Z) {
        p.z -= CHUNK_SIZE_Z;
        neighbor.z = +1;
    } else {
        neighbor.z = 0;
    }

    *outChunkLocalPos = p;
    return [self neighborAtPosition:neighbor];
}

- (voxel_t)voxelAtPoint:(GSIntegerVector3)p
{
    return [[self neighborVoxelAtPoint:&p] voxelAtLocalPosition:p];
}

- (unsigned)lightAtPoint:(GSIntegerVector3)p getter:(GSBuffer* (^)(GSChunkVoxelData *c))getter
{
    assert(CHUNK_LIGHTING_MAX < (1ull << (sizeof(unsigned)*8)) && "unsigned int must be large enough to store light values");
    
    GSChunkVoxelData *chunk = [self neighborVoxelAtPoint:&p];
    GSBuffer *lightingBuffer = getter(chunk);
    
    unsigned lightLevel = (unsigned)[lightingBuffer valueAtPosition:p];

    assert(lightLevel >= 0 && lightLevel <= CHUNK_LIGHTING_MAX);
    
    return lightLevel;
}

@end
