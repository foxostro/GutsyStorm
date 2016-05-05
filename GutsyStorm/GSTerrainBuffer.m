//
//  GSTerrainBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainBuffer.h"
#import "GSVoxel.h"
#import "GSErrorCodes.h"
#import "SyscallWrappers.h"
#import "GSNeighborhood.h"
#import "GSVoxel.h" // for INDEX_BOX
#import "GSStopwatch.h"


/* Get points to sample for voxel lighting. */
static void samplingPoints(size_t count, vector_float3 * _Nonnull sample, vector_long3 normal);


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

    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    if(p.x >= 0 && p.x < dim.x &&
       p.y >= 0 && p.y < dim.y &&
       p.z >= 0 && p.z < dim.z) {
        return _data[INDEX_BOX(p, GSZeroIntVec3, dim)];
    } else {
        return 0;
    }
}

- (GSTerrainBufferElement)lightForVertexAtPoint:(vector_float3)vertexPosInWorldSpace
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

- (void)saveToFile:(nonnull NSURL *)url
             queue:(nonnull dispatch_queue_t)queue
             group:(nonnull dispatch_group_t)group
            header:(nullable NSData *)headerData
{
    NSParameterAssert(url);
    NSParameterAssert([url isFileURL]);

    dispatch_group_enter(group);

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

            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }

            dispatch_group_leave(group);
        });
    });
}

- (nonnull instancetype)copySubBufferWithMinCorner:(vector_long3)srcMinP maxCorner:(vector_long3)srcMaxP
{
    NSParameterAssert(srcMaxP.y - srcMinP.y == CHUNK_SIZE_Y);
    
    vector_long3 p = GSZeroIntVec3, newDimensions = srcMaxP - srcMinP;
    GSTerrainBufferElement *dstBuf = [[self class] allocateBufferWithLength:BUFFER_SIZE_IN_BYTES(newDimensions)];

    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, newDimensions)
    {
        vector_long3 srcPos = p + srcMinP + _offsetFromChunkLocalSpace;
        assert(srcPos.x >= 0 && srcPos.y >= 0 && srcPos.z >= 0);
        assert(srcPos.x < _dimensions.x && srcPos.y < _dimensions.y && srcPos.z < _dimensions.z);

        size_t srcOffset = INDEX_BOX(srcPos, GSZeroIntVec3, _dimensions);
        assert(srcOffset < _dimensions.x*_dimensions.y*_dimensions.z);

        size_t dstOffset = INDEX_BOX(p, GSZeroIntVec3, newDimensions);
        assert(dstOffset < newDimensions.x*newDimensions.y*newDimensions.z);

        memcpy(dstBuf + dstOffset, _data + srcOffset, newDimensions.y * sizeof(GSTerrainBufferElement));
    }
    
    id aBuffer = [[[self class] alloc] initWithDimensions:newDimensions takeOwnershipOfAlignedData:dstBuf];

    return aBuffer;
}

- (nonnull instancetype)copyWithEditAtPosition:(vector_long3)chunkLocalPos value:(GSTerrainBufferElement)newValue
{
    vector_long3 dim = self.dimensions;
    vector_long3 p = chunkLocalPos + _offsetFromChunkLocalSpace;

    assert(chunkLocalPos.x >= 0 && chunkLocalPos.x < dim.x);
    assert(chunkLocalPos.y >= 0 && chunkLocalPos.y < dim.y);
    assert(chunkLocalPos.z >= 0 && chunkLocalPos.z < dim.z);

    GSTerrainBufferElement *modifiedData = [[self class] cloneBuffer:_data len:BUFFER_SIZE_IN_BYTES(dim)];
    modifiedData[INDEX_BOX(p, GSZeroIntVec3, dim)] = newValue;

    GSTerrainBuffer *buffer = [[GSTerrainBuffer alloc] initWithDimensions:dim takeOwnershipOfAlignedData:modifiedData];

    return buffer;
}

- (nonnull GSTerrainBufferElement *)data
{
    assert(_data);
    return _data;
}

@end


static void samplingPoints(size_t count, vector_float3 * _Nonnull sample, vector_long3 n)
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