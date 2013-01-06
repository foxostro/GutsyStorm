//
//  GSLightingBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "Voxel.h"
#import "GSLightingBuffer.h"
#import "GSChunkVoxelData.h"

#define BUFFER_SIZE_IN_BYTES (_dimensions.x * _dimensions.y * _dimensions.z * sizeof(uint8_t))

// Columns in the y-axis are contiguous in memory.
#define INDEX_INTO_LIGHTING_BUFFER(p) ((size_t)(((p.x)*_dimensions.y*_dimensions.z) + ((p.z)*_dimensions.y) + (p.y)))

static void samplingPoints(size_t count, GLKVector3 *sample, GSIntegerVector3 normal);

@implementation GSLightingBuffer
{
    GSIntegerVector3 _offsetFromChunkLocalSpace;
}

- (id)initWithDimensions:(GSIntegerVector3)dim
{
    self = [super init];
    if (self) {
        assert(dim.x >= CHUNK_SIZE_X);
        assert(dim.y >= CHUNK_SIZE_Y);
        assert(dim.z >= CHUNK_SIZE_Z);
        
        _dimensions = dim;
        
        _offsetFromChunkLocalSpace = GSIntegerVector3_Make((_dimensions.x - CHUNK_SIZE_X) / 2,
                                                          (_dimensions.y - CHUNK_SIZE_Y) / 2,
                                                          (_dimensions.z - CHUNK_SIZE_Z) / 2);
        
        _lightingBuffer = malloc(BUFFER_SIZE_IN_BYTES);
        
        if(!_lightingBuffer) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }
        
        _lockLightingBuffer = [[GSReaderWriterLock alloc] init];
        
        [self clear];
    }

    return self;
}

- (id)init
{
    return [self initWithDimensions:chunkSize];
}

- (void)dealloc
{
    free(_lightingBuffer);
    [_lockLightingBuffer release];
    [super dealloc];
}

- (uint8_t)lightAtPoint:(GSIntegerVector3)chunkLocalPos
{
    assert(lightingBuffer);
    
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, _offsetFromChunkLocalSpace);
    
    if(p.x >= 0 && p.x < _dimensions.x && p.y >= 0 && p.y < _dimensions.y && p.z >= 0 && p.z < _dimensions.z) {
        return _lightingBuffer[INDEX_INTO_LIGHTING_BUFFER(p)];
    } else {
        return 0;
    }
}

- (uint8_t)lightForVertexAtPoint:(GLKVector3)vertexPosInWorldSpace
                      withNormal:(GSIntegerVector3)normal
                            minP:(GLKVector3)minP
{
    static const size_t count = 4;
    GLKVector3 sample[count];
    float light;
    int i;

    assert(lightingBuffer);

    samplingPoints(count, sample, normal);

    for(light = 0.0f, i = 0; i < count; ++i)
    {
        GSIntegerVector3 clp = GSIntegerVector3_Make(truncf(sample[i].x + vertexPosInWorldSpace.x - minP.x),
                                                     truncf(sample[i].y + vertexPosInWorldSpace.y - minP.y),
                                                     truncf(sample[i].z + vertexPosInWorldSpace.z - minP.z));
        
        assert(clp.x >= -1 && clp.x <= CHUNK_SIZE_X);
        assert(clp.y >= -1 && clp.y <= CHUNK_SIZE_Y);
        assert(clp.z >= -1 && clp.z <= CHUNK_SIZE_Z);

        light += [self lightAtPoint:clp] / (float)count;
    }

    return light;
}

- (void)readerAccessToBufferUsingBlock:(void (^)(void))block
{
    [_lockLightingBuffer lockForReading];
    block();
    [_lockLightingBuffer unlockForReading];
}


- (void)writerAccessToBufferUsingBlock:(void (^)(void))block
{
    [_lockLightingBuffer lockForWriting];
    block();
    [_lockLightingBuffer unlockForWriting];
}

- (void)clear
{
    bzero(_lightingBuffer, BUFFER_SIZE_IN_BYTES);
}

- (void)saveToFile:(NSURL *)url
{
    [_lockLightingBuffer lockForReading];
    [[NSData dataWithBytes:_lightingBuffer length:BUFFER_SIZE_IN_BYTES] writeToURL:url atomically:YES];
    [_lockLightingBuffer unlockForReading];
}

- (BOOL)tryToLoadFromFile:(NSURL *)url completionHandler:(void (^)(void))completionHandler
{
    BOOL success = NO;
    
    [_lockLightingBuffer lockForWriting];
    
    // If the file does not exist then do nothing.
    if([url checkResourceIsReachableAndReturnError:NULL]) {
        // Read the contents of the file into "sunlight.lightingBuffer".
        NSData *data = [[NSData alloc] initWithContentsOfURL:url];
        if([data length] == BUFFER_SIZE_IN_BYTES) {
            [data getBytes:_lightingBuffer length:BUFFER_SIZE_IN_BYTES];
            success = YES;
        }
        [data release];
    }
    
    if(success) {
        completionHandler();
    }
    
    [_lockLightingBuffer unlockForWriting];
    
    return success;
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
