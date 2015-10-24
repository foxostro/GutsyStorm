//
//  FoxByteBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "FoxTerrainBuffer.h"
#import "FoxVoxel.h"
#import "FoxErrorCodes.h"
#import "SyscallWrappers.h"
#import "FoxNeighborhood.h"
#import "FoxVoxel.h" // for INDEX_BOX


static void samplingPoints(size_t count, vector_float3 *sample, vector_long3 normal);


@implementation FoxTerrainBuffer

+ (void)newBufferFromFile:(NSURL *)url
               dimensions:(vector_long3)dimensions
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(FoxTerrainBuffer *aBuffer, NSError *error))completionHandler
{
    // If the file does not exist then do nothing.
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSString *reason = [NSString stringWithFormat:@"File not found for buffer: %@", url];
        completionHandler(nil, [NSError errorWithDomain:FoxErrorDomain
                                                   code:FoxFileNotFoundError
                                               userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
        return;
    }

    const int fd = Open(url, O_RDONLY, 0);
    const size_t len = BUFFER_SIZE_IN_BYTES(dimensions);

    dispatch_read(fd, len, queue, ^(dispatch_data_t dd, int error) {
        Close(fd);

        if(error) {
            char errorMsg[LINE_MAX];
            strerror_r(-error, errorMsg, LINE_MAX);
            NSString *reason = [NSString stringWithFormat:@"error with read(fd=%d): %s [%d]", fd, errorMsg, error];
            completionHandler(nil, [NSError errorWithDomain:NSPOSIXErrorDomain
                                                       code:error
                                                   userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
            return;
        }

        if(dispatch_data_get_size(dd) != len) {
            NSString *reason = [NSString stringWithFormat:@"Read %zu bytes from file, but expected %zu bytes.",
                                dispatch_data_get_size(dd), len];
            completionHandler(nil, [NSError errorWithDomain:FoxErrorDomain
                                                       code:FoxInvalidChunkDataOnDiskError
                                                   userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
            return;
        }

        // Map the data object to a buffer in memory and use it to initialize a new FoxByteBuffer object.
        {
            size_t size = 0;
            const void *buffer = NULL;
            NS_VALID_UNTIL_END_OF_SCOPE dispatch_data_t mappedData = dispatch_data_create_map(dd, &buffer, &size);
            assert(len == size);
            FoxTerrainBuffer *aBuffer = [[self alloc] initWithDimensions:dimensions data:(const terrain_buffer_element_t *)buffer];
            completionHandler(aBuffer, nil);
        }
    });
}

+ (nullable instancetype)newBufferFromLargerRawBuffer:(const terrain_buffer_element_t * _Nonnull)srcBuf
                                              srcMinP:(vector_long3)combinedMinP
                                              srcMaxP:(vector_long3)combinedMaxP
{
    static const vector_long3 dimensions = {CHUNK_SIZE_X+2, CHUNK_SIZE_Y, CHUNK_SIZE_Z+2};

    assert(srcBuf);
    assert(combinedMaxP.y - combinedMinP.y == CHUNK_SIZE_Y);

    vector_long3 offset = GSMakeIntegerVector3(1, 0, 1);
    vector_long3 a = GSMakeIntegerVector3(-1, 0, -1);
    vector_long3 b = GSMakeIntegerVector3(CHUNK_SIZE_X+1, 0, CHUNK_SIZE_Z+1);
    vector_long3 p; // loop counter

    terrain_buffer_element_t *dstBuf = malloc(BUFFER_SIZE_IN_BYTES(dimensions));

    FOR_Y_COLUMN_IN_BOX(p, a, b)
    {
        size_t srcOffset = INDEX_BOX(p, combinedMinP, combinedMaxP);
        size_t dstOffset = INDEX_BOX(p + offset, GSZeroIntVec3, dimensions);
        memcpy(dstBuf + dstOffset, srcBuf + srcOffset, CHUNK_SIZE_Y * sizeof(terrain_buffer_element_t));
    }

    id aBuffer = [[self alloc] initWithDimensions:dimensions data:dstBuf];

    free(dstBuf);

    return aBuffer;
}

- (nullable instancetype)initWithDimensions:(vector_long3)dim
{
    self = [super init];
    if (self) {
        assert(dim.x >= CHUNK_SIZE_X);
        assert(dim.y >= CHUNK_SIZE_Y);
        assert(dim.z >= CHUNK_SIZE_Z);

        _dimensions = dim;
        _offsetFromChunkLocalSpace = (dim - GSChunkSizeIntVec3) / 2;
        _data = malloc(BUFFER_SIZE_IN_BYTES(dim));

        if(!_data) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }

        bzero(_data, BUFFER_SIZE_IN_BYTES(dim));
    }
    
    return self;
}

- (nullable instancetype)initWithDimensions:(vector_long3)dim data:(const terrain_buffer_element_t * _Nonnull)data
{
    assert(data);
    self = [self initWithDimensions:dim]; // NOTE: this call will allocate memory for _data
    if (self) {
        assert(_data);
        memcpy(_data, data, BUFFER_SIZE_IN_BYTES(dim));
    }
    return self;
}

- (void)dealloc
{
    free(_data);
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // FoxBuffer is immutable. Return self rather than perform a deep copy.
}

- (terrain_buffer_element_t)valueAtPosition:(vector_long3)chunkLocalPos
{
    assert(_data);

    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    if(p.x >= 0 && p.x < dim.x &&
       p.y >= 0 && p.y < dim.y &&
       p.z >= 0 && p.z < dim.z) {
        return _data[INDEX_INTO_LIGHTING_BUFFER(dim, p)];
    } else {
        return 0;
    }
}

- (terrain_buffer_element_t)lightForVertexAtPoint:(vector_float3)vertexPosInWorldSpace
                               withNormal:(vector_long3)normal
                                     minP:(vector_float3)minP
{
    static const size_t count = 4;
    vector_float3 sample[count];
    float light;
    int i;

    assert(_data);

    samplingPoints(count, sample, normal);

    for(light = 0.0f, i = 0; i < count; ++i)
    {
        vector_long3 clp = GSMakeIntegerVector3(truncf(sample[i].x + vertexPosInWorldSpace.x - minP.x),
                                                     truncf(sample[i].y + vertexPosInWorldSpace.y - minP.y),
                                                     truncf(sample[i].z + vertexPosInWorldSpace.z - minP.z));

        assert(clp.x >= -1 && clp.x <= CHUNK_SIZE_X);
        assert(clp.y >= -1 && clp.y <= CHUNK_SIZE_Y);
        assert(clp.z >= -1 && clp.z <= CHUNK_SIZE_Z);

        light += [self valueAtPosition:clp] / (float)count;
    }
    
    return light;
}

- (void)saveToFile:(NSURL *)url queue:(dispatch_queue_t)queue group:(dispatch_group_t)group
{
    dispatch_group_enter(group);

    dispatch_data_t dd = dispatch_data_create(_data, BUFFER_SIZE_IN_BYTES(self.dimensions),
                                                    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                    DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    dispatch_async(queue, ^{
        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

        dispatch_write(fd, dd, queue, ^(dispatch_data_t data, int error) {
            Close(fd);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_group_leave(group);
        });
    });
}

- (void)copyToCombinedNeighborhoodBuffer:(terrain_buffer_element_t *)dstBuf
                                   count:(NSUInteger)count
                                neighbor:(neighbor_index_t)neighbor
{
    static ssize_t offsetsX[CHUNK_NUM_NEIGHBORS];
    static ssize_t offsetsZ[CHUNK_NUM_NEIGHBORS];
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        for(neighbor_index_t i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            vector_float3 offset = [FoxNeighborhood offsetForNeighborIndex:i];
            offsetsX[i] = offset.x;
            offsetsZ[i] = offset.z;
        }
    });
    
    ssize_t offsetX = offsetsX[neighbor];
    ssize_t offsetZ = offsetsZ[neighbor];

    vector_long3 p;
    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
    {
        assert(p.x >= 0 && p.x < GSChunkSizeIntVec3.x);
        assert(p.y >= 0 && p.y < GSChunkSizeIntVec3.y);
        assert(p.z >= 0 && p.z < GSChunkSizeIntVec3.z);

        size_t dstIdx = INDEX_BOX(GSMakeIntegerVector3(p.x+offsetX, p.y, p.z+offsetZ), combinedMinP, combinedMaxP);
        size_t srcIdx = INDEX_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3);

        assert(dstIdx < count);
        assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));

        memcpy(&dstBuf[dstIdx], &_data[srcIdx], CHUNK_SIZE_Y*sizeof(dstBuf[0]));
    }
}

- (FoxTerrainBuffer *)copyWithEditAtPosition:(vector_long3)chunkLocalPos value:(terrain_buffer_element_t)newValue
{
    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(chunkLocalPos.x >= 0 && chunkLocalPos.x < dim.x);
    assert(chunkLocalPos.y >= 0 && chunkLocalPos.y < dim.y);
    assert(chunkLocalPos.z >= 0 && chunkLocalPos.z < dim.z);

    terrain_buffer_element_t *modifiedData = malloc(BUFFER_SIZE_IN_BYTES(dim));
    
    if(!modifiedData) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating modifiedData."];
    }

    memcpy(modifiedData, _data, BUFFER_SIZE_IN_BYTES(dim));
    modifiedData[INDEX_INTO_LIGHTING_BUFFER(dim, p)] = newValue;

    FoxTerrainBuffer *buffer = [[FoxTerrainBuffer alloc] initWithDimensions:dim data:modifiedData];

    free(modifiedData);

    return buffer;
}

- (const terrain_buffer_element_t * _Nonnull)data
{
    return _data;
}

@end


static void samplingPoints(size_t count, vector_float3 *sample, vector_long3 n)
{
    assert(count == 4);
    assert(sample);

    const float a = 0.5f;

    if(n.x==1 && n.y==0 && n.z==0) {
        sample[0] = vector_make(+a, -a, -a);
        sample[1] = vector_make(+a, -a, +a);
        sample[2] = vector_make(+a, +a, -a);
        sample[3] = vector_make(+a, +a, +a);
    } else if(n.x==-1 && n.y==0 && n.z==0) {
        sample[0] = vector_make(-a, -a, -a);
        sample[1] = vector_make(-a, -a, +a);
        sample[2] = vector_make(-a, +a, -a);
        sample[3] = vector_make(-a, +a, +a);
    } else if(n.x==0 && n.y==1 && n.z==0) {
        sample[0] = vector_make(-a, +a, -a);
        sample[1] = vector_make(-a, +a, +a);
        sample[2] = vector_make(+a, +a, -a);
        sample[3] = vector_make(+a, +a, +a);
    } else if(n.x==0 && n.y==-1 && n.z==0) {
        sample[0] = vector_make(-a, -a, -a);
        sample[1] = vector_make(-a, -a, +a);
        sample[2] = vector_make(+a, -a, -a);
        sample[3] = vector_make(+a, -a, +a);
    } else if(n.x==0 && n.y==0 && n.z==1) {
        sample[0] = vector_make(-a, -a, +a);
        sample[1] = vector_make(-a, +a, +a);
        sample[2] = vector_make(+a, -a, +a);
        sample[3] = vector_make(+a, +a, +a);
    } else if(n.x==0 && n.y==0 && n.z==-1) {
        sample[0] = vector_make(-a, -a, -a);
        sample[1] = vector_make(-a, +a, -a);
        sample[2] = vector_make(+a, -a, -a);
        sample[3] = vector_make(+a, +a, -a);
    } else {
        assert(!"shouldn't get here");
        sample[0] = vector_make(0, 0, 0);
        sample[1] = vector_make(0, 0, 0);
        sample[2] = vector_make(0, 0, 0);
        sample[3] = vector_make(0, 0, 0);
    }
}