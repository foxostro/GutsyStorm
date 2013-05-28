//
//  GSByteBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKQuaternion.h>
#import "GSBuffer.h"
#import "Voxel.h"
#import "GutsyStormErrorCodes.h"
#import "GSNeighborhood.h"
#import <GLKit/GLKQuaternion.h> // used by Voxel.h
#import "Voxel.h" // for INDEX_BOX
#import "NSDataCompression.h"


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 normal);


@implementation GSBuffer

+ (void)newBufferFromFile:(NSURL *)url
               dimensions:(GSIntegerVector3)dimensions
                    queue:(dispatch_queue_t)queue
        completionHandler:(void (^)(GSBuffer *aBuffer, NSError *error))completionHandler
{
    // If the file does not exist then do nothing.
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSString *reason = [NSString stringWithFormat:@"File not found for buffer: %@", url];
        completionHandler(nil, [NSError errorWithDomain:GSErrorDomain
                                                   code:GSFileNotFoundError
                                               userInfo:@{NSLocalizedFailureReasonErrorKey:reason}]);
        return;
    }
    
    NSError *error = nil;
    NSData *compressedData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
    
    if(compressedData) {
        NSData *uncompressedData = [compressedData zlibInflate];
        GSBuffer *aBuffer = [[self alloc] initWithDimensions:dimensions data:(const buffer_element_t *)[uncompressedData bytes]];
        completionHandler(aBuffer, nil);
    } else {
        completionHandler(nil, error);
    }
}

+ (id)newBufferFromLargerRawBuffer:(const buffer_element_t *)srcBuf
                           srcMinP:(GSIntegerVector3)combinedMinP
                           srcMaxP:(GSIntegerVector3)combinedMaxP
{
    static const GSIntegerVector3 dimensions = {CHUNK_SIZE_X+2, CHUNK_SIZE_Y+2, CHUNK_SIZE_Z+2};

    assert(srcBuf);
    
    GSIntegerVector3 p; // loop counter
    
    GSIntegerVector3 a = GSIntegerVector3_Make(-1, -1, -1);
    GSIntegerVector3 b = GSIntegerVector3_Make(CHUNK_SIZE_X+1, CHUNK_SIZE_Y+1, CHUNK_SIZE_Z+1);

    buffer_element_t *dstBuf = malloc(BUFFER_SIZE_IN_BYTES(dimensions));
    if(!dstBuf) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for dstBuf."];
    }
    
    FOR_Y_COLUMN_IN_BOX(p, a, b)
    {
        size_t srcIndex = INDEX_BOX(p, combinedMinP, combinedMaxP);
        size_t dstIndex = INDEX_BOX(p, a, b);
        memcpy(dstBuf + dstIndex, srcBuf + srcIndex, dimensions.y * sizeof(buffer_element_t));
    }

    id aBuffer = [[self alloc] initWithDimensions:dimensions data:dstBuf];

    free(dstBuf);

    return aBuffer;
}

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    self = [super init];
    if (self) {
        assert(dim.x >= CHUNK_SIZE_X);
        assert(dim.y >= CHUNK_SIZE_Y);
        assert(dim.z >= CHUNK_SIZE_Z);

        _dimensions = dim;

        _offsetFromChunkLocalSpace = GSIntegerVector3_Make((dim.x - CHUNK_SIZE_X) / 2,
                                                           (dim.y - CHUNK_SIZE_Y) / 2,
                                                           (dim.z - CHUNK_SIZE_Z) / 2);

        _data = malloc(BUFFER_SIZE_IN_BYTES(dim));

        if(!_data) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }

        bzero(_data, BUFFER_SIZE_IN_BYTES(dim));
    }
    
    return self;
}

- (id)initWithDimensions:(GSIntegerVector3)dim data:(const buffer_element_t *)data
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

- (id)copyWithZone:(NSZone *)zone
{
    return self; // GSBuffer is immutable. Return self rather than perform a deep copy.
}

- (buffer_element_t)valueAtPosition:(GSIntegerVector3)chunkLocalPos
{
    assert(_data);

    GSIntegerVector3 dim = self.dimensions;
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);

    if(p.x >= 0 && p.x < dim.x &&
       p.y >= 0 && p.y < dim.y &&
       p.z >= 0 && p.z < dim.z) {
        return _data[INDEX_INTO_LIGHTING_BUFFER(dim, p)];
    } else {
        return 0;
    }
}

- (buffer_element_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                               withNormal:(GSIntegerVector3)normal
                                     minP:(GLKVector3)minP
{
    static const size_t count = 4;
    GLKVector3 sample[count];
    float light;
    int i;

    assert(_data);

    samplingPoints(count, sample, normal);

    for(light = 0.0f, i = 0; i < count; ++i)
    {
        GSIntegerVector3 clp = GSIntegerVector3_Make(truncf(sample[i].x + vertexPosInWorldSpace.x - minP.x),
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
    NSData *uncompressedData = [NSData dataWithBytes:_data length:BUFFER_SIZE_IN_BYTES(self.dimensions)];
    dispatch_group_async(group, queue, ^{
        NSData *compressedData = [uncompressedData zlibDeflate];
        [compressedData writeToURL:url atomically:YES];
    });
}

- (void)copyToCombinedNeighborhoodBuffer:(buffer_element_t *)dstBuf
                                   count:(NSUInteger)count
                  positionInNeighborhood:(GSNeighborOffset)positionInNeighborhood
{
    assert(positionInNeighborhood.x >= -1 && positionInNeighborhood.x <= +1);
    assert(positionInNeighborhood.y >= -1 && positionInNeighborhood.y <= +1);
    assert(positionInNeighborhood.z >= -1 && positionInNeighborhood.z <= +1);

    GSIntegerVector3 p;
    FOR_Y_COLUMN_IN_BOX(p, ivecZero, chunkSize)
    {
        assert(p.x >= 0 && p.x < chunkSize.x);
        assert(p.y >= 0 && p.y < chunkSize.y);
        assert(p.z >= 0 && p.z < chunkSize.z);

        const GSIntegerVector3 offsetP = GSIntegerVector3_Add(p, positionInNeighborhood);
        size_t dstIdx = INDEX_BOX(offsetP, combinedMinP, combinedMaxP);
        size_t srcIdx = INDEX_BOX(p, ivecZero, chunkSize);

        assert(dstIdx < count);
        assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));

        memcpy(&dstBuf[dstIdx], &_data[srcIdx], CHUNK_SIZE_Y*sizeof(dstBuf[0]));
    }
}

- (GSBuffer *)copyWithEditAtPosition:(GSIntegerVector3)chunkLocalPos value:(buffer_element_t)newValue
{
    GSIntegerVector3 dim = self.dimensions;
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);

    assert(chunkLocalPos.x >= 0 && chunkLocalPos.x < dim.x);
    assert(chunkLocalPos.y >= 0 && chunkLocalPos.y < dim.y);
    assert(chunkLocalPos.z >= 0 && chunkLocalPos.z < dim.z);

    buffer_element_t *modifiedData = malloc(BUFFER_SIZE_IN_BYTES(dim));
    
    if(!modifiedData) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating modifiedData."];
    }

    memcpy(modifiedData, _data, BUFFER_SIZE_IN_BYTES(dim));
    modifiedData[INDEX_INTO_LIGHTING_BUFFER(dim, p)] = newValue;

    GSBuffer *buffer = [[GSBuffer alloc] initWithDimensions:dim data:modifiedData];

    free(modifiedData);

    return buffer;
}

- (const buffer_element_t *)data
{
    return _data;
}

@end


static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 n)
{
    assert(count == 4);
    assert(sample);

    const float a = 0.5f;

    if(n.x==1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(+a, -a, -a);
        sample[1] = GLKVector3Make(+a, -a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==-1 && n.y==0 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(-a, +a, -a);
        sample[3] = GLKVector3Make(-a, +a, +a);
    } else if(n.x==0 && n.y==1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, +a, -a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, +a, -a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==-1 && n.z==0) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, -a, +a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, -a, +a);
    } else if(n.x==0 && n.y==0 && n.z==1) {
        sample[0] = GLKVector3Make(-a, -a, +a);
        sample[1] = GLKVector3Make(-a, +a, +a);
        sample[2] = GLKVector3Make(+a, -a, +a);
        sample[3] = GLKVector3Make(+a, +a, +a);
    } else if(n.x==0 && n.y==0 && n.z==-1) {
        sample[0] = GLKVector3Make(-a, -a, -a);
        sample[1] = GLKVector3Make(-a, +a, -a);
        sample[2] = GLKVector3Make(+a, -a, -a);
        sample[3] = GLKVector3Make(+a, +a, -a);
    } else {
        assert(!"shouldn't get here");
        sample[0] = GLKVector3Make(0, 0, 0);
        sample[1] = GLKVector3Make(0, 0, 0);
        sample[2] = GLKVector3Make(0, 0, 0);
        sample[3] = GLKVector3Make(0, 0, 0);
    }
}