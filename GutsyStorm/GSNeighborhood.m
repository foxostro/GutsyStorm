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
- (void)setNeighborAtPosition:(GSNeighborOffset)p neighbor:(GSChunkVoxelData *)neighbor;

/* Returns YES if all neighbor chunk positions are consistent and if there are no duplicates and no empty neighbor slots.
 * A neighborhood may be inconsistent if the chunks assigned as neighbors are not in the expected positions.
 * A neighborhood may be inconsistent if a neighbor slot has been left empty (set to nil).
 * A neighborhood may be inconsistent if the same chunk has been assigned to fill two separate neighbor slots.
 */
- (BOOL)neighborhoodIsConsistent;

@end


@implementation GSNeighborhood
{
    GSChunkVoxelData *_neighbors[3][3][3];
}

- (id)init
{
    assert(!"call -initWithCenterPoint:chunkProducer: instead");
    
    self = [super init];
    if (self) {
        [self clear];
    }
    
    return self;
}

- (id)initWithCenterPoint:(GLKVector3)centerMinP chunkProducer:(GSChunkVoxelData * (^)(GLKVector3 p))chunkProducer
{
    if (self = [super init]) {
        [self clear];
        
        const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
        GSIntegerVector3 positionInNeighborhood;
        FOR_BOX(positionInNeighborhood, a, b)
        {
            GLKVector3 offset = GLKVector3Make(positionInNeighborhood.x * CHUNK_SIZE_X,
                                               positionInNeighborhood.y * CHUNK_SIZE_Y,
                                               positionInNeighborhood.z * CHUNK_SIZE_Z);
            GLKVector3 neighborMinP = GLKVector3Add(centerMinP, offset);
            GSChunkVoxelData *voxels = chunkProducer(neighborMinP);
            [self setNeighborAtPosition:positionInNeighborhood neighbor:voxels];
        }
        
        assert([self neighborhoodIsConsistent]);
    }
    
    return self;
}

- (void)dealloc
{
    [self clear];
}

- (void)clear
{
    const GSNeighborOffset a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSNeighborOffset positionInNeighborhood;
    FOR_BOX(positionInNeighborhood, a, b)
    {
        [self setNeighborAtPosition:positionInNeighborhood neighbor:nil];
    }
}

- (GSChunkVoxelData *)neighborAtPosition:(GSNeighborOffset)p
{
    assert(p.x >= -1 && p.x <= +1);
    assert(p.y >= -1 && p.y <= +1);
    assert(p.z >= -1 && p.z <= +1);
    return _neighbors[p.x+1][p.y+1][p.z+1];
}

- (void)setNeighborAtPosition:(GSNeighborOffset)p neighbor:(GSChunkVoxelData *)neighbor
{
    assert(p.x >= -1 && p.x <= +1);
    assert(p.y >= -1 && p.y <= +1);
    assert(p.z >= -1 && p.z <= +1);
    _neighbors[p.x+1][p.y+1][p.z+1] = neighbor;
}

- (BOOL)neighborhoodIsConsistent
{
    const GSNeighborOffset a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSNeighborOffset p, q;
    
    FOR_BOX(p, a, b)
    {
        if([self neighborAtPosition:p] == nil) {
            return NO;
        }
    }
    
    FOR_BOX(p, a, b)
    {
        FOR_BOX(q, a, b)
        {
            if(0 != memcmp(&p, &q, sizeof(GSNeighborOffset))) {
                if([self neighborAtPosition:p] == [self neighborAtPosition:q]) {
                    return NO;
                }
            }
        }
    }
    
    GLKVector3 centerMinP = [self neighborAtPosition:ivecZero].minP;
    FOR_BOX(p, a, b)
    {
        GLKVector3 offset = GLKVector3Make(p.x * CHUNK_SIZE_X, p.y * CHUNK_SIZE_Y, p.z * CHUNK_SIZE_Z);
        GLKVector3 expectedNeighborMinP = GLKVector3Add(centerMinP, offset);
        GLKVector3 actualNeighborMinP = [self neighborAtPosition:p].minP;
        if(GLKVector3Distance(expectedNeighborMinP, actualNeighborMinP) > FLT_EPSILON) {
            return NO;
        }
    }
    
    return YES;
}

- (void)enumerateNeighborsWithBlock:(void (^)(GSChunkVoxelData*))block
{
    const GSNeighborOffset a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSNeighborOffset p;
    FOR_BOX(p, a, b)
    {
        block([self neighborAtPosition:p]);
    }
}

- (void)enumerateNeighborsWithBlock2:(void (^)(GSIntegerVector3 p, GSChunkVoxelData*))block
{
    const GSNeighborOffset a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+2, +2, +2);
    GSNeighborOffset p;
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

    [self enumerateNeighborsWithBlock2:^(GSNeighborOffset positionInNeighborhood, GSChunkVoxelData *voxels) {
        [voxels.voxels copyToCombinedNeighborhoodBuffer:(buffer_element_t *)combinedVoxelData
                                                  count:count
                                 positionInNeighborhood:positionInNeighborhood];
    }];

    return combinedVoxelData;
}

/* Every neighboring chunk is referred to by a vector offset describing the position of the neighboring chunk relative to the local
 * chunk. For example, (-1, 0, 0). The local chunk is described by (0, 0, 0).
 *
 * This method gets the vector offset for the neighboring chunk that contains the specified local position.
 *
 * The specified local position must be in the Moore neighborhood of the local chunk.
 */
- (GSIntegerVector3)neighborOffsetForLocalPosition:(GSNeighborOffset)p
{
    assert(p.x >= -CHUNK_SIZE_X);
    assert(p.y >= -CHUNK_SIZE_Y);
    assert(p.z >= -CHUNK_SIZE_Z);
    assert(p.x < 2*CHUNK_SIZE_X);
    assert(p.y < 2*CHUNK_SIZE_Y);
    assert(p.z < 2*CHUNK_SIZE_Z);
    
    GSNeighborOffset neighbor = ivecZero;
    
    if(p.x < 0) {
        neighbor.x = -1;
    } else if(p.x >= CHUNK_SIZE_X) {
        neighbor.x = +1;
    } else {
        neighbor.x = 0;
    }
    
    if(p.y < 0) {
        neighbor.y = -1;
    } else if(p.y >= CHUNK_SIZE_Y) {
        neighbor.y = +1;
    } else {
        neighbor.y = 0;
    }
    
    if(p.z < 0) {
        neighbor.z = -1;
    } else if(p.z >= CHUNK_SIZE_Z) {
        neighbor.z = +1;
    } else {
        neighbor.z = 0;
    }
    
    return neighbor;
}

- (voxel_t)voxelAtPoint:(GSIntegerVector3)chunkLocalPosition
{
    GSNeighborOffset neighborOffset = [self neighborOffsetForLocalPosition:chunkLocalPosition];
    GSIntegerVector3 coordinateSpaceOffset = GSIntegerVector3_Make(neighborOffset.x * -CHUNK_SIZE_X,
                                                                   neighborOffset.y * -CHUNK_SIZE_Y,
                                                                   neighborOffset.z * -CHUNK_SIZE_Z);
    GSIntegerVector3 translatedPosition = GSIntegerVector3_Add(chunkLocalPosition, coordinateSpaceOffset);
    GSChunkVoxelData *neighborChunk = [self neighborAtPosition:neighborOffset];
    voxel_t voxel = [neighborChunk voxelAtLocalPosition:translatedPosition];
    return voxel;
}

- (unsigned)lightAtPoint:(GSIntegerVector3)p getter:(GSBuffer* (^)(GSChunkVoxelData *c))getter
{
    assert(CHUNK_LIGHTING_MAX < (1ull << (sizeof(unsigned)*8)) && "unsigned int must be large enough to store light values");
    GSIntegerVector3 neighborOffset = [self neighborOffsetForLocalPosition:p];
    GSChunkVoxelData *neighborChunk = [self neighborAtPosition:neighborOffset];
    GSBuffer *lightingBuffer = getter(neighborChunk);
    unsigned lightLevel = (unsigned)[lightingBuffer valueAtPosition:p];
    assert(lightLevel >= 0 && lightLevel <= CHUNK_LIGHTING_MAX);
    return lightLevel;
}

@end
