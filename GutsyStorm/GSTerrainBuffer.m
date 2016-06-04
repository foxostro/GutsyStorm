//
//  GSTerrainBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainBuffer.h"
#import "GSErrorCodes.h"
#import "SyscallWrappers.h"
#import "GSNeighborhood.h"
#import "GSStopwatch.h"
#import "GSVectorUtils.h"
#import "GSBox.h"


static dispatch_semaphore_t gSemaFileDescriptorLimit;
static const long OPEN_FILE_LIMIT = 100; // Don't open more than this many file descriptors open at once for saving.


@implementation GSTerrainBuffer

@synthesize offsetFromChunkLocalSpace = _offsetFromChunkLocalSpace;

+ (nonnull GSTerrainBufferElement *)allocateBufferWithLength:(NSUInteger)len
{
    GSTerrainBufferElement *buffer = NSAllocateMemoryPages(len);
    if (!buffer) {
        [NSException raise:NSMallocException format:@"Out of memory allocating buffer for GSTerrainBuffer."];
    }
    return buffer;
}

+ (nonnull GSTerrainBufferElement *)cloneBuffer:(nonnull const GSTerrainBufferElement *)src len:(NSUInteger)len
{
    assert(0 == ((NSUInteger)src % NSPageSize()));
    GSTerrainBufferElement *dst = [self allocateBufferWithLength:len];
    NSCopyMemoryPages(src, dst, len);
    return dst;
}

+ (nonnull GSTerrainBufferElement *)cloneUnalignedBuffer:(nonnull const GSTerrainBufferElement*)src len:(NSUInteger)len
{
    GSTerrainBufferElement *dst = [self allocateBufferWithLength:len];
    memcpy(dst, src, len);
    return dst;
}

+ (void)deallocateBuffer:(nullable GSTerrainBufferElement *)buffer len:(NSUInteger)len
{
    NSDeallocateMemoryPages(buffer, len);
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim
{
    NSParameterAssert(dim.x >= CHUNK_SIZE_X && dim.x >= 0);
    NSParameterAssert(dim.y >= CHUNK_SIZE_Y && dim.y >= 0);
    NSParameterAssert(dim.z >= CHUNK_SIZE_Z && dim.z >= 0);
    
    if (self = [super init]) {
        _dimensions = dim;
        _offsetFromChunkLocalSpace = (dim - GSChunkSizeIntVec3) / 2;
        _data = [[self class] allocateBufferWithLength:BUFFER_SIZE_IN_BYTES(dim)];
    }
    
    return self;
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                         copyUnalignedData:(nonnull const GSTerrainBufferElement *)data
{
    NSParameterAssert(dim.x >= CHUNK_SIZE_X && dim.x >= 0);
    NSParameterAssert(dim.y >= CHUNK_SIZE_Y && dim.y >= 0);
    NSParameterAssert(dim.z >= CHUNK_SIZE_Z && dim.z >= 0);

    if (self = [super init]) {
        _dimensions = dim;
        _offsetFromChunkLocalSpace = (dim - GSChunkSizeIntVec3) / 2;
        _data = [[self class] cloneUnalignedBuffer:data len:BUFFER_SIZE_IN_BYTES(dim)];
    }

    return self;
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                takeOwnershipOfAlignedData:(nonnull GSTerrainBufferElement *)data
{
    NSParameterAssert(dim.x >= CHUNK_SIZE_X && dim.x >= 0);
    NSParameterAssert(dim.y >= CHUNK_SIZE_Y && dim.y >= 0);
    NSParameterAssert(dim.z >= CHUNK_SIZE_Z && dim.z >= 0);
    NSParameterAssert(0 == (NSUInteger)data % NSPageSize());
    
    if (self = [super init]) {
        _dimensions = dim;
        _offsetFromChunkLocalSpace = (dim - GSChunkSizeIntVec3) / 2;
        _data = data;
    }
    
    return self;
}

- (nonnull instancetype)initWithDimensions:(vector_long3)dim
                          cloneAlignedData:(const GSTerrainBufferElement * _Nonnull)data
{
    NSParameterAssert(dim.x >= CHUNK_SIZE_X && dim.x >= 0);
    NSParameterAssert(dim.y >= CHUNK_SIZE_Y && dim.y >= 0);
    NSParameterAssert(dim.z >= CHUNK_SIZE_Z && dim.z >= 0);
    NSParameterAssert(0 == (NSUInteger)data % NSPageSize());

    if (self = [super init]) {
        _dimensions = dim;
        _offsetFromChunkLocalSpace = (dim - GSChunkSizeIntVec3) / 2;
        _data = [[self class] cloneBuffer:data len:BUFFER_SIZE_IN_BYTES(dim)];
    }
    
    return self;
}

- (void)dealloc
{
    [[self class] deallocateBuffer:_data len:BUFFER_SIZE_IN_BYTES(_dimensions)];
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // GSTerrainBuffer is immutable. Return self rather than perform a deep copy.
}

- (GSTerrainBufferElement)valueAtPosition:(vector_long3)chunkLocalPos
{
    assert(_data);

    GSIntAABB selfBox = { GSZeroIntVec3, _dimensions };
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    if(p.x >= selfBox.mins.x && p.x < selfBox.maxs.x &&
       p.y >= selfBox.mins.y && p.y < selfBox.maxs.y &&
       p.z >= selfBox.mins.z && p.z < selfBox.maxs.z) {
        return _data[INDEX_BOX(p, selfBox)];
    } else {
        return 0;
    }
}

- (void)saveToFile:(nonnull NSURL *)url
             queue:(nonnull dispatch_queue_t)queue
             group:(nonnull dispatch_group_t)group
            header:(nullable NSData *)headerData
{
    NSParameterAssert(url);
    NSParameterAssert([url isFileURL]);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct rlimit limit = {0};
        
        if (getrlimit(RLIMIT_NOFILE, &limit) != 0) {
            raiseExceptionForPOSIXError(errno, @"Failed to retrieve RLIMIT_NOFILE.");
        }
        
        // RLIMIT_NOFILE is almost certainly higher than OPEN_FILE_LIMIT, but why not simply verify that it's valid?
        gSemaFileDescriptorLimit = dispatch_semaphore_create(MIN(OPEN_FILE_LIMIT, limit.rlim_cur));
    });

    dispatch_group_enter(group);
    
    dispatch_semaphore_wait(gSemaFileDescriptorLimit, DISPATCH_TIME_FOREVER);

    dispatch_data_t dd;
    
    if ([headerData length] == 0) {
        dd = dispatch_data_create(_data, BUFFER_SIZE_IN_BYTES(self.dimensions),
                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                  DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    } else {
        dispatch_data_t header = dispatch_data_create([headerData bytes], [headerData length],
                                      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                      DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dispatch_data_t terrain = dispatch_data_create(_data, BUFFER_SIZE_IN_BYTES(self.dimensions),
                                                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                       DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        dd = dispatch_data_create_concat(header, terrain);
    }

    dispatch_async(queue, ^{
        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);

        dispatch_write(fd, dd, queue, ^(dispatch_data_t data, int error) {
            Close(fd);
            dispatch_semaphore_signal(gSemaFileDescriptorLimit);

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_group_leave(group);
        });
    });
}

- (nonnull instancetype)copySubBufferFromSubrange:(GSIntAABB * _Nonnull)srcBox
{
    NSParameterAssert(srcBox && (srcBox->maxs.y - srcBox->mins.y == CHUNK_SIZE_Y));
    
    vector_long3 p = GSZeroIntVec3, newDimensions = srcBox->maxs - srcBox->mins;
    GSTerrainBufferElement *dstBuf = [[self class] allocateBufferWithLength:BUFFER_SIZE_IN_BYTES(newDimensions)];
    
    GSIntAABB thisBufferBox = { GSZeroIntVec3, _dimensions };
    GSIntAABB relSrcBox = { GSZeroIntVec3, newDimensions };

    FOR_Y_COLUMN_IN_BOX(p, relSrcBox)
    {
        vector_long3 srcPos = p + srcBox->mins + _offsetFromChunkLocalSpace;
        assert(srcPos.x >= 0 && srcPos.y >= 0 && srcPos.z >= 0);
        assert(srcPos.x < _dimensions.x && srcPos.y < _dimensions.y && srcPos.z < _dimensions.z);

        size_t srcOffset = INDEX_BOX(srcPos, thisBufferBox);
        assert(srcOffset < _dimensions.x*_dimensions.y*_dimensions.z);

        size_t dstOffset = INDEX_BOX(p, relSrcBox);
        assert(dstOffset < newDimensions.x*newDimensions.y*newDimensions.z);

        memcpy(dstBuf + dstOffset, _data + srcOffset, newDimensions.y * sizeof(GSTerrainBufferElement));
    }
    
    id aBuffer = [[[self class] alloc] initWithDimensions:newDimensions takeOwnershipOfAlignedData:dstBuf];

    return aBuffer;
}

- (nonnull instancetype)copyWithEditAtPosition:(vector_long3)chunkLocalPos
                                         value:(GSTerrainBufferElement)newValue
                                     operation:(GSVoxelBitwiseOp)op
{
    GSIntAABB selfBox = { GSZeroIntVec3, _dimensions };
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(chunkLocalPos.x >= selfBox.mins.x && chunkLocalPos.x < selfBox.maxs.x);
    assert(chunkLocalPos.y >= selfBox.mins.y && chunkLocalPos.y < selfBox.maxs.y);
    assert(chunkLocalPos.z >= selfBox.mins.z && chunkLocalPos.z < selfBox.maxs.z);

    GSTerrainBufferElement *modifiedData = [[self class] cloneBuffer:_data len:BUFFER_SIZE_IN_BYTES(_dimensions)];
    
    size_t idx = INDEX_BOX(p, selfBox);
    
    switch(op)
    {
    case Set:
        modifiedData[idx] = newValue;
        break;

    case BitwiseOr:
        modifiedData[idx] |= newValue;
        break;
        
    case BitwiseAnd:
        modifiedData[idx] &= newValue;
        break;
    }

    GSTerrainBuffer *buffer = [[GSTerrainBuffer alloc] initWithDimensions:_dimensions
                                               takeOwnershipOfAlignedData:modifiedData];

    return buffer;
}

- (nonnull GSTerrainBufferElement *)data
{
    assert(_data);
    return _data;
}

@end