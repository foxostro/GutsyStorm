//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSIntegerVector3.h"
#import "GSChunkVoxelData.h"
#import "GSRay.h"
#import "GSBoxedVector.h"
#import "GSChunkStore.h"
#import "GSNeighborhood.h"
#import "GutsyStormErrorCodes.h"
#import "GSMutableBuffer.h"
#import "NSDataCompression.h"


@interface GSChunkVoxelData ()

- (GSBuffer *)newVoxelDataBufferWithGenerator:(terrain_generator_t)generator
                                postProcessor:(terrain_post_processor_t)postProcessor;
- (GSBuffer *)newVoxelDataBufferFromFileOrFromScratchWithGenerator:(terrain_generator_t)generator
                                                     postProcessor:(terrain_post_processor_t)postProcessor;

@end


@implementation GSChunkVoxelData
{
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
    dispatch_queue_t _chunkTaskQueue;
}

@synthesize minP;

+ (NSString *)fileNameForVoxelDataFromMinP:(GLKVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}

- (id)initWithMinP:(GLKVector3)mp
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    queueForSaving:(dispatch_queue_t)queueForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         generator:(terrain_generator_t)generator
     postProcessor:(terrain_post_processor_t)postProcessor
{
    if (self = [super init]) {
        assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

        minP = mp;
        
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        dispatch_retain(_groupForSaving);
        
        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);

        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        dispatch_retain(_queueForSaving);
        
        _folder = folder;
        
        _voxels = [self newVoxelDataBufferFromFileOrFromScratchWithGenerator:generator
                                                               postProcessor:postProcessor];
    }
    
    return self;
}

- (id)initWithMinP:(GLKVector3)mp
            folder:(NSURL *)folder
    groupForSaving:(dispatch_group_t)groupForSaving
    queueForSaving:(dispatch_queue_t)queueForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
              data:(GSBuffer *)data
{
    if (self = [super init]) {
        minP = mp;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        dispatch_retain(_groupForSaving);

        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);

        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        dispatch_retain(_queueForSaving);

        _folder = folder;
        _voxels = [GSMutableBuffer newMutableBufferWithBuffer:data];
    }

    return self;
}

- (void)dealloc
{
    dispatch_release(_groupForSaving);
    dispatch_release(_chunkTaskQueue);
    dispatch_release(_queueForSaving);
}

- (id)copyWithZone:(NSZone *)zone
{
    return self; // all voxel data objects are immutable, so return self instead of deep copying
}

- (voxel_t)voxelAtLocalPosition:(GSIntegerVector3)p
{
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    buffer_element_t value = [_voxels valueAtPosition:p];
    voxel_t voxel = *((const voxel_t *)&value);
    return voxel;
}

/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is translated so
 * that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that, for example, the width of
 * the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (GSBuffer *)newVoxelDataBufferWithGenerator:(terrain_generator_t)generator
                                postProcessor:(terrain_post_processor_t)postProcessor
{
    GSIntegerVector3 p, a, b;
    a = GSIntegerVector3_Make(-1, -1, -1);
    b = GSIntegerVector3_Make(chunkSize.x+1, chunkSize.y+1, chunkSize.z+1);

    const size_t count = (b.x-a.x) * (b.y-a.y) * (b.z-a.z);
    voxel_t *voxels = calloc(count, sizeof(voxel_t));

    // First, generate voxels for the region of the chunk, plus a 1 block wide border.
    // Note that whether the block is outside or not is calculated later.
    FOR_BOX(p, a, b)
    {
        generator(GLKVector3Add(GLKVector3Make(p.x, p.y, p.z), self.minP), &voxels[INDEX_BOX(p, a, b)]);
    }

    // Post-process the voxels to add ramps, &c.
    postProcessor(count, voxels, a, b);

    // Copy the voxels for the chunk to their final destination.
    GSMutableBuffer *data = [[GSMutableBuffer alloc] initWithDimensions:chunkSize];
    voxel_t *buf = (voxel_t *)[data mutableData];
    
    FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
    {
        size_t srcOffset = INDEX_BOX(p, a, b);
        size_t dstOffset = INDEX_BOX(p, ivecZero, chunkSize);
        memcpy(buf + dstOffset, voxels + srcOffset, CHUNK_SIZE_Y * sizeof(voxel_t));
    }
    
    free(voxels);

    return data;
}

- (void)saveToFile
{
    NSString *fileName = [GSChunkVoxelData fileNameForVoxelDataFromMinP:self.minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    [self.voxels saveToFile:url queue:_queueForSaving group:_groupForSaving];
}

- (GSBuffer *)newVoxelDataBufferFromFileOrFromScratchWithGenerator:(terrain_generator_t)generator
                                                     postProcessor:(terrain_post_processor_t)postProcessor
{
    __block GSBuffer *myBuffer = nil;

    NSString *fileName = [GSChunkVoxelData fileNameForVoxelDataFromMinP:self.minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    [GSBuffer newBufferFromFile:url
                     dimensions:chunkSize
                          queue:_chunkTaskQueue
              completionHandler:^(GSBuffer *aBuffer, NSError *error) {
                  if(aBuffer) {
                      myBuffer = aBuffer;
                  } else {
                      myBuffer = [self newVoxelDataBufferWithGenerator:generator postProcessor:postProcessor];
                      [myBuffer saveToFile:url queue:_queueForSaving group:_groupForSaving];
                  }
                  
                  dispatch_semaphore_signal(sema);
              }];
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    assert(myBuffer);
    dispatch_release(sema);

    return myBuffer;
}

- (GSChunkVoxelData *)copyWithEditAtPoint:(GLKVector3)pos block:(voxel_t)newBlock
{
    GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    buffer_element_t newValue = *((buffer_element_t *)&newBlock);
    GSBuffer *modified = [self.voxels copyWithEditAtPosition:chunkLocalPos value:newValue];
    GSChunkVoxelData *modifiedVoxelData = [[GSChunkVoxelData alloc] initWithMinP:minP
                                                                          folder:_folder
                                                                  groupForSaving:_groupForSaving
                                                                  queueForSaving:_queueForSaving
                                                                  chunkTaskQueue:_chunkTaskQueue
                                                                            data:modified];
    return modifiedVoxelData;
}

@end
