//
//  FoxChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxIntegerVector3.h"
#import "FoxChunkVoxelData.h"
#import "FoxRay.h"
#import "FoxBoxedVector.h"
#import "FoxChunkStore.h"
#import "FoxNeighborhood.h"
#import "FoxErrorCodes.h"
#import "SyscallWrappers.h"
#import "FoxMutableBuffer.h"


@interface FoxChunkVoxelData ()

- (void)markOutsideVoxels:(FoxMutableBuffer *)data;
- (FoxTerrainBuffer *)newVoxelDataBufferWithGenerator:(terrain_generator_t)generator
                                postProcessor:(terrain_post_processor_t)postProcessor;
- (FoxTerrainBuffer *)newVoxelDataBufferFromFileOrFromScratchWithGenerator:(terrain_generator_t)generator
                                                     postProcessor:(terrain_post_processor_t)postProcessor;

@end


@implementation FoxChunkVoxelData
{
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
    dispatch_queue_t _chunkTaskQueue;
}

@synthesize minP;

+ (NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}

- (instancetype)initWithMinP:(vector_float3)mp
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                   generator:(terrain_generator_t)generator
               postProcessor:(terrain_post_processor_t)postProcessor
{
    assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

    if (self = [super init]) {
        minP = mp;
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        _voxels = [self newVoxelDataBufferFromFileOrFromScratchWithGenerator:generator postProcessor:postProcessor];
    }

    return self;
}

- (instancetype)initWithMinP:(vector_float3)mp
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                        data:(FoxTerrainBuffer *)data
{
    if (self = [super init]) {
        minP = mp;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        FoxMutableBuffer *dataWithUpdatedOutside = [FoxMutableBuffer newMutableBufferWithBuffer:data];
        [self markOutsideVoxels:dataWithUpdatedOutside];
        _voxels = dataWithUpdatedOutside;
    }

    return self;
}

- (void)dealloc
{
    _groupForSaving = NULL;
    _chunkTaskQueue = NULL;
    _queueForSaving = NULL;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // all voxel data objects are immutable, so return self instead of deep copying
}

- (voxel_t)voxelAtLocalPosition:(vector_long3)p
{
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    terrain_buffer_element_t value = [_voxels valueAtPosition:p];
    voxel_t voxel = *((const voxel_t *)&value);
    return voxel;
}

- (void)markOutsideVoxels:(FoxMutableBuffer *)data
{
    vector_long3 p;

    // Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
    // We assume here that the chunk is the height of the world.
    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, chunkSize)
    {
        // Get the y value of the highest non-empty voxel in the chunk.
        ssize_t heightOfHighestVoxel;
        for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
        {
            voxel_t *voxel = (voxel_t *)[data pointerToValueAtPosition:GSMakeIntegerVector3(p.x, heightOfHighestVoxel, p.z)];
            
            if(voxel->opaque) {
                break;
            }
        }
        
        for(p.y = 0; p.y < chunkSize.y; ++p.y)
        {
            voxel_t *voxel = (voxel_t *)[data pointerToValueAtPosition:p];
            voxel->outside = (p.y >= heightOfHighestVoxel);
        }
    }

    // Determine voxels in the chunk which are exposed to air on top.
    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, chunkSize)
    {
        // Find a voxel which is empty and is directly above a cube voxel.
        p.y = CHUNK_SIZE_Y-1;
        voxel_type_t prevType = ((voxel_t *)[data pointerToValueAtPosition:p])->type;
        for(p.y = CHUNK_SIZE_Y-2; p.y >= 0; --p.y)
        {
            voxel_t *voxel = (voxel_t *)[data pointerToValueAtPosition:p];

            // XXX: It would be better to store the relationships between voxel types in some other way. Not here.
            voxel->exposedToAirOnTop = (voxel->type!=VOXEL_TYPE_EMPTY && prevType==VOXEL_TYPE_EMPTY) ||
                                       (voxel->type==VOXEL_TYPE_CUBE && prevType==VOXEL_TYPE_CORNER_OUTSIDE) ||
                                       (voxel->type==VOXEL_TYPE_CORNER_INSIDE && prevType==VOXEL_TYPE_CORNER_OUTSIDE) ||
                                       (voxel->type==VOXEL_TYPE_CUBE && prevType==VOXEL_TYPE_RAMP);

            prevType = voxel->type;
        }
    }
}

/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (FoxTerrainBuffer *)newVoxelDataBufferWithGenerator:(terrain_generator_t)generator
                                postProcessor:(terrain_post_processor_t)postProcessor
{
    vector_float3 thisMinP = self.minP;
    vector_long3 p, a, b;
    a = GSMakeIntegerVector3(-2, 0, -2);
    b = GSMakeIntegerVector3(chunkSize.x+2, chunkSize.y, chunkSize.z+2);

    const size_t count = (b.x-a.x) * (b.y-a.y) * (b.z-a.z);
    voxel_t *voxels = calloc(count, sizeof(voxel_t));

    // First, generate voxels for the region of the chunk, plus a 1 block wide border.
    // Note that whether the block is outside or not is calculated later.
    // XXX: Remove this loop and replace with a modified generator() that performs batch voxel generation.
    FOR_BOX(p, a, b)
    {
        generator(vector_make(p.x, p.y, p.z) + thisMinP, &voxels[INDEX_BOX(p, a, b)]);
    }

    // Post-process the voxels to add ramps, &c.
    postProcessor(count, voxels, a, b);

    // Copy the voxels for the chunk to their final destination.
    // TODO: Copy each column wholesale using memcpy
    // XXX: I suspect that a highly efficient bit-blit could be written which copies voxels much faster than this.
    FoxMutableBuffer *data = [[FoxMutableBuffer alloc] initWithDimensions:chunkSize];
    voxel_t *buf = (voxel_t *)[data mutableData];
    FOR_BOX(p, GSZeroIntVec3, chunkSize)
    {
        buf[INDEX_BOX(p, GSZeroIntVec3, chunkSize)] = voxels[INDEX_BOX(p, a, b)];
    }

    free(voxels);

    [self markOutsideVoxels:data];

    return data;
}

- (void)saveToFile
{
    NSString *fileName = [FoxChunkVoxelData fileNameForVoxelDataFromMinP:self.minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    [self.voxels saveToFile:url queue:_queueForSaving group:_groupForSaving];
}

- (FoxTerrainBuffer *)newVoxelDataBufferFromFileOrFromScratchWithGenerator:(terrain_generator_t)generator
                                                     postProcessor:(terrain_post_processor_t)postProcessor
{
    FoxTerrainBuffer *buffer = nil;

    @autoreleasepool {
        NSString *fileName = [FoxChunkVoxelData fileNameForVoxelDataFromMinP:self.minP];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:[url path]
                                              options:NSDataReadingMapped
                                                error:&error];
        BOOL goodSize = [data length] == BUFFER_SIZE_IN_BYTES(chunkSize);

        if (data && goodSize) {
            if (!goodSize) {
                NSLog(@"ERROR: bad size for chunk data; assuming data corruption");
            }
            const terrain_buffer_element_t * _Nullable bytes = [data bytes];
            assert(bytes);
            buffer = [[FoxTerrainBuffer alloc] initWithDimensions:chunkSize
                                                             data:(const terrain_buffer_element_t * _Nonnull)bytes];
        } else {
            buffer = [self newVoxelDataBufferWithGenerator:generator postProcessor:postProcessor];
            [buffer saveToFile:url queue:_queueForSaving group:_groupForSaving];
        }
        
        assert(buffer);
    }

    return buffer;
}

- (FoxChunkVoxelData *)copyWithEditAtPoint:(vector_float3)pos block:(voxel_t)newBlock
{
    vector_long3 chunkLocalPos = GSMakeIntegerVector3(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    terrain_buffer_element_t newValue = *((terrain_buffer_element_t *)&newBlock);
    FoxTerrainBuffer *modified = [self.voxels copyWithEditAtPosition:chunkLocalPos value:newValue];
    FoxChunkVoxelData *modifiedVoxelData = [[FoxChunkVoxelData alloc] initWithMinP:minP
                                                                          folder:_folder
                                                                  groupForSaving:_groupForSaving
                                                                  queueForSaving:_queueForSaving
                                                                  chunkTaskQueue:_chunkTaskQueue
                                                                            data:modified];
    return modifiedVoxelData;
}

@end