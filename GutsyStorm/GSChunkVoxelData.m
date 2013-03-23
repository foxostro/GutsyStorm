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
#import "GutsyStormErrorCodes.h"
#import "SyscallWrappers.h"

static const GSIntegerVector3 combinedMinP = {-CHUNK_SIZE_X, 0, -CHUNK_SIZE_Z};
static const GSIntegerVector3 combinedMaxP = {2*CHUNK_SIZE_X, CHUNK_SIZE_Y, 2*CHUNK_SIZE_Z};


@interface GSChunkVoxelData ()

- (void)destroyVoxelData;
- (void)allocateVoxelData;
- (void)loadVoxelDataFromURL:(NSURL *)url completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
- (void)recalcOutsideVoxelsNoLock;
- (void)generateVoxelDataWithGenerator:(terrain_generator_t)generator
                         postProcessor:(terrain_post_processor_t)postProcessor;
- (void)saveVoxelDataToFile;
- (void)loadOrGenerateVoxelData:(terrain_generator_t)generator
                  postProcessor:(terrain_post_processor_t)postProcessor
              completionHandler:(void (^)(void))completionHandler;

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
    self = [super init];
    if (self) {
        assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

        minP = mp;
        
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        dispatch_retain(_groupForSaving);
        
        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);

        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        dispatch_retain(_queueForSaving);
        
        _folder = folder;
        
        _lockVoxelData = [[GSReaderWriterLock alloc] init];
        [_lockVoxelData lockForWriting]; // This is locked initially and unlocked at the end of the first update.
        _voxelData = NULL;
        
        // Fire off asynchronous task to load or generate voxel data.
        dispatch_async(_chunkTaskQueue, ^{
            [self allocateVoxelData];
            [self loadOrGenerateVoxelData:generator
                            postProcessor:postProcessor
                        completionHandler:^{
                            [_lockVoxelData unlockForWriting];
                            // We don't need to call -voxelDataWasModified in the special case of initialization.
                        }];
        });
    }
    
    return self;
}

- (void)dealloc
{
    dispatch_release(_groupForSaving);
    dispatch_release(_chunkTaskQueue);
    dispatch_release(_queueForSaving);
    [self destroyVoxelData];
}

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t)voxelAtLocalPosition:(GSIntegerVector3)p
{
    return *[self pointerToVoxelAtLocalPosition:p];
}

// Assumes the caller is already holding "lockVoxelData".
- (voxel_t *)pointerToVoxelAtLocalPosition:(GSIntegerVector3)p
{
    assert(_voxelData);
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    
    size_t idx = INDEX_BOX(p, ivecZero, chunkSize);
    assert(idx >= 0 && idx < (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z));
    
    return &_voxelData[idx];
}

- (void)voxelDataWasModified
{
    [self recalcOutsideVoxelsNoLock];
    [self saveVoxelDataToFile];
}

- (void)readerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    [_lockVoxelData lockForReading];
    block();
    [_lockVoxelData unlockForReading];
}

- (BOOL)tryReaderAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    if(![_lockVoxelData tryLockForReading]) {
        return NO;
    } else {
        block();
        [_lockVoxelData unlockForReading];
        return YES;
    }
}

- (void)writerAccessToVoxelDataUsingBlock:(void (^)(void))block
{
    [_lockVoxelData lockForWriting];
    block();
    [self voxelDataWasModified];
    [_lockVoxelData unlockForWriting];
}

/* Copy the voxel data for the neighborhood into a new buffer and return the buffer. If the method would block when taking the
 * locks on the neighborhood then instead return NULL. The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y
 * elements in size and may be indexed using the INDEX2 macro.
 * Assumes the caller has already locked the voxelData for chunks in the neighborhood (for reading).
 */
- (voxel_t *)newVoxelBufferWithNeighborhood:(GSNeighborhood *)neighborhood
{
    static const size_t size = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;
    
    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    voxel_t *combinedVoxelData = combinedVoxelData = malloc(size*sizeof(voxel_t));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
    }
    
    static ssize_t offsetsX[CHUNK_NUM_NEIGHBORS];
    static ssize_t offsetsZ[CHUNK_NUM_NEIGHBORS];
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        for(neighbor_index_t i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            GLKVector3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            offsetsX[i] = offset.x;
            offsetsZ[i] = offset.z;
        }
    });
    
    [neighborhood enumerateNeighborsWithBlock2:^(neighbor_index_t i, GSChunkVoxelData *voxels) {
        const voxel_t *data = voxels.voxelData;
        ssize_t offsetX = offsetsX[i];
        ssize_t offsetZ = offsetsZ[i];
        
        GSIntegerVector3 p;
        FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
        {
            assert(p.x >= 0 && p.x < chunkSize.x);
            assert(p.y >= 0 && p.y < chunkSize.y);
            assert(p.z >= 0 && p.z < chunkSize.z);
            
            size_t dstIdx = INDEX_BOX(GSIntegerVector3_Make(p.x+offsetX, p.y, p.z+offsetZ), combinedMinP, combinedMaxP);
            size_t srcIdx = INDEX_BOX(p, ivecZero, chunkSize);
            
            assert(dstIdx < size);
            assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));
            assert(sizeof(combinedVoxelData[0]) == sizeof(data[0]));

            memcpy(&combinedVoxelData[dstIdx], &data[srcIdx], CHUNK_SIZE_Y*sizeof(combinedVoxelData[0]));
        }
    }];
    
    return combinedVoxelData;
}

- (void)saveVoxelDataToFile
{
    dispatch_group_enter(_groupForSaving);
    dispatch_async(_queueForSaving, ^{
        NSURL *url = [NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:self.minP]
                            relativeToURL:_folder];

        const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);

        [_lockVoxelData lockForReading];
        dispatch_data_t voxelData = dispatch_data_create(_voxelData, len,
                                                         dispatch_get_global_queue(0, 0),
                                                         DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        [_lockVoxelData unlockForReading];

        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

        dispatch_write(fd, voxelData, _queueForSaving, ^(dispatch_data_t data, int error) {
            Close(fd);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_release(voxelData);
            dispatch_group_leave(_groupForSaving);
        });
    });
}

// Assumes the caller is already holding "lockVoxelData".
- (void)allocateVoxelData
{
    [self destroyVoxelData];
    
    _voxelData = malloc(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t));
    if(!_voxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for chunk's voxelData"];
    }
}

// Assumes the caller is already holding "lockVoxelData".
- (void)destroyVoxelData
{
    free(_voxelData);
    _voxelData = NULL;
}

// Assumes the caller is already holding "lockVoxelData".
- (void)recalcOutsideVoxelsNoLock
{
    GSIntegerVector3 p;

    // Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
    // We assume here that the chunk is the height of the world.
    FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
    {
        // Get the y value of the highest non-empty voxel in the chunk.
        ssize_t heightOfHighestVoxel;
        for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
        {
            voxel_t *voxel = [self pointerToVoxelAtLocalPosition:GSIntegerVector3_Make(p.x, heightOfHighestVoxel, p.z)];
            
            if(voxel->opaque) {
                break;
            }
        }
        
        for(p.y = 0; p.y < chunkSize.y; ++p.y)
        {
            [self pointerToVoxelAtLocalPosition:p]->outside = (p.y >= heightOfHighestVoxel);
        }
    }

    // Determine voxels in the chunk which are exposed to air on top.
    FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
    {
        // Find a voxel which is empty and is directly above a cube voxel.
        p.y = CHUNK_SIZE_Y-1;
        voxel_type_t prevType = [self pointerToVoxelAtLocalPosition:p]->type;
        for(p.y = CHUNK_SIZE_Y-2; p.y >= 0; --p.y)
        {
            voxel_t *voxel = [self pointerToVoxelAtLocalPosition:p];

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
 *
 * Assumes the caller already holds "lockVoxelData" for writing.
 */
- (void)generateVoxelDataWithGenerator:(terrain_generator_t)generator
                         postProcessor:(terrain_post_processor_t)postProcessor
{
    GSIntegerVector3 p, a, b;
    a = GSIntegerVector3_Make(-1, 0, -1);
    b = GSIntegerVector3_Make(chunkSize.x+1, chunkSize.y, chunkSize.z+1);

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
    FOR_BOX(p, ivecZero, chunkSize)
    {
        _voxelData[INDEX_BOX(p, ivecZero, chunkSize)] = voxels[INDEX_BOX(p, a, b)];
    }

    free(voxels);
}

// Attempt to asynchronously load voxel data from file.
- (void)loadVoxelDataFromURL:(NSURL *)url completionHandler:(void (^)(BOOL success, NSError *error))completionHandler
{
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        completionHandler(NO, [NSError errorWithDomain:GSErrorDomain
                                                  code:GSFileNotFoundError
                                              userInfo:@{NSLocalizedFailureReasonErrorKey:@"Voxel data file is not present."}]);
        return;

    }

    const size_t len = CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z * sizeof(voxel_t);
    int fd = Open(url, O_RDONLY, 0);
    dispatch_read(fd, len, _chunkTaskQueue, ^(dispatch_data_t data, int error) {
        Close(fd);

        if(error) {
            completionHandler(NO,
                              [NSError errorWithDomain:GSErrorDomain
                                                  code:GSInvalidChunkDataOnDiskError
                                              userInfo:@{NSLocalizedFailureReasonErrorKey:@"File I/O Error"}]);
            return;
        }
        
        if(dispatch_data_get_size(data) != len) {
            completionHandler(NO,
                              [NSError errorWithDomain:GSErrorDomain
                                                  code:GSInvalidChunkDataOnDiskError
                                              userInfo:@{NSLocalizedFailureReasonErrorKey:@"Voxel data file is " \
                                                                                           "of unexpected length."}]);
            return;
        }

        // Map the data object to a buffer in memory and copy to our internal voxel data buffer.
        size_t size = 0;
        const void *buffer = NULL;
        dispatch_data_t mappedData = dispatch_data_create_map(data, &buffer, &size);
        assert(len == size);
        memcpy(_voxelData, buffer, len);
        dispatch_release(mappedData);

        completionHandler(YES, nil);
    });
}

- (void)loadOrGenerateVoxelData:(terrain_generator_t)generator
                  postProcessor:(terrain_post_processor_t)postProcessor
              completionHandler:(void (^)(void))completionHandler
{
    [self loadVoxelDataFromURL:[NSURL URLWithString:[GSChunkVoxelData fileNameForVoxelDataFromMinP:self.minP]
                                      relativeToURL:_folder]
             completionHandler:^(BOOL success, NSError *error) {
                 if(error) {
                     if((error.code == GSInvalidChunkDataOnDiskError) || (error.code == GSFileNotFoundError)) {
                         [self generateVoxelDataWithGenerator:generator
                                                postProcessor:postProcessor];
                         [self saveVoxelDataToFile];
                     } else {
                         [NSException raise:@"Runtime Error" format:@"Error %ld: %@", (long)error.code, error.localizedDescription];
                     }
                 }

                 [self recalcOutsideVoxelsNoLock];

                 completionHandler();
             }];
}

@end