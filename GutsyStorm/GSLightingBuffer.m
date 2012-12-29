//
//  GSLightingBuffer.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/18/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSLightingBuffer.h"
#import "GSChunkVoxelData.h"

#define BUFFER_SIZE_IN_BYTES (dimensions.x * dimensions.y * dimensions.z * sizeof(uint8_t))

// Columns in the y-axis are contiguous in memory.
#define INDEX_INTO_LIGHTING_BUFFER(p) ((size_t)(((p.x)*dimensions.y*dimensions.z) + ((p.z)*dimensions.y) + (p.y)))

static void samplingPoints(size_t count, GSIntegerVector3 *sample, GSIntegerVector3 normal);


@implementation GSLightingBuffer

@synthesize lockLightingBuffer;
@synthesize lightingBuffer;
@synthesize dimensions;

- (id)initWithDimensions:(GSIntegerVector3)_dimensions
{
    self = [super init];
    if (self) {
        assert(_dimensions.x >= CHUNK_SIZE_X);
        assert(_dimensions.y >= CHUNK_SIZE_Y);
        assert(_dimensions.z >= CHUNK_SIZE_Z);
        
        dimensions = _dimensions;
        
        offsetFromChunkLocalSpace = GSIntegerVector3_Make((dimensions.x - CHUNK_SIZE_X) / 2,
                                                          (dimensions.y - CHUNK_SIZE_Y) / 2,
                                                          (dimensions.z - CHUNK_SIZE_Z) / 2);
        
        lightingBuffer = malloc(BUFFER_SIZE_IN_BYTES);
        
        if(!lightingBuffer) {
            [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for lighting buffer."];
        }
        
        lockLightingBuffer = [[GSReaderWriterLock alloc] init];
        
        [self clear];
    }

    return self;
}

- (id)init
{
    return [self initWithDimensions:GSIntegerVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z)];
}

- (void)dealloc
{
    free(lightingBuffer);
    [lockLightingBuffer release];
    [super dealloc];
}

- (uint8_t)lightAtPoint:(GSIntegerVector3)chunkLocalPos
{
    assert(lightingBuffer);
    
    GSIntegerVector3 p = GSIntegerVector3_Add(chunkLocalPos, offsetFromChunkLocalSpace);
    
    if(p.x >= 0 && p.x < dimensions.x && p.y >= 0 && p.y < dimensions.y && p.z >= 0 && p.z < dimensions.z) {
        return lightingBuffer[INDEX_INTO_LIGHTING_BUFFER(p)];
    } else {
        return 0;
    }
}

- (uint8_t)lightForVertexAtPoint:(GSIntegerVector3)chunkLocalPos
                      withNormal:(GSIntegerVector3)normal
{
    static const size_t count = 4;
    GSIntegerVector3 sample[count];
    unsigned light;

    assert(lightingBuffer);
    assert(lighting);
    assert(chunkLocalPos.x >= 0 && chunkLocalPos.x < CHUNK_SIZE_X);
    assert(chunkLocalPos.y >= 0 && chunkLocalPos.y < CHUNK_SIZE_Y);
    assert(chunkLocalPos.z >= 0 && chunkLocalPos.z < CHUNK_SIZE_Z);

    samplingPoints(count, sample, normal);
    light = 0;
    
    for(int i=0; i<count; ++i)
    {
        light += [self lightAtPoint:GSIntegerVector3_Add(chunkLocalPos, sample[i])];
    }

    return light / count;
}

- (void)readerAccessToBufferUsingBlock:(void (^)(void))block
{
    [lockLightingBuffer lockForReading];
    block();
    [lockLightingBuffer unlockForReading];
}


- (void)writerAccessToBufferUsingBlock:(void (^)(void))block
{
    [lockLightingBuffer lockForWriting];
    block();
    [lockLightingBuffer unlockForWriting];
}

- (void)clear
{
    bzero(lightingBuffer, BUFFER_SIZE_IN_BYTES);
}

- (void)saveToFile:(NSURL *)url
{
    const size_t len = dimensions.x * dimensions.y * dimensions.z * sizeof(uint8_t);
    
    [lockLightingBuffer lockForReading];
    [[NSData dataWithBytes:lightingBuffer length:len] writeToURL:url atomically:YES];
    [lockLightingBuffer unlockForReading];
}

- (BOOL)tryToLoadFromFile:(NSURL *)url completionHandler:(void (^)(void))completionHandler
{
    BOOL success = NO;
    
    [lockLightingBuffer lockForWriting];
    
    // If the file does not exist then do nothing.
    if([url checkResourceIsReachableAndReturnError:NULL]) {
        const size_t len = dimensions.x * dimensions.y * dimensions.z * sizeof(uint8_t);
        
        // Read the contents of the file into "sunlight.lightingBuffer".
        NSData *data = [[NSData alloc] initWithContentsOfURL:url];
        if([data length] == len) {
            [data getBytes:lightingBuffer length:len];
            success = YES;
        }
        [data release];
    }
    
    if(success) {
        completionHandler();
    }
    
    [lockLightingBuffer unlockForWriting];
    
    return success;
}

@end

static void samplingPoints(size_t count, GSIntegerVector3 *sample, GSIntegerVector3 normal)
{
    assert(count == 4);
    assert(sample);
    
    /* The normal must be unit length and point along one of the eight cardinal directions. */
    assert(normal.x == 0 || normal.x == -1 || normal.x == +1);
    assert(normal.y == 0 || normal.y == -1 || normal.y == +1);
    assert(normal.z == 0 || normal.z == -1 || normal.z == +1);
    assert(  (normal.x != 0 && normal.y == 0 && normal.z == 0) ||
           (normal.y != 0 && normal.x == 0 && normal.z == 0) ||
           (normal.z != 0 && normal.x == 0 && normal.y == 0)  );

    if(normal.x != 0) { // If the normal is along the x-axis.
        sample[0] = GSIntegerVector3_Make(normal.x, -1, -1);
        sample[1] = GSIntegerVector3_Make(normal.x, -1, +1);
        sample[2] = GSIntegerVector3_Make(normal.x, +1, -1);
        sample[3] = GSIntegerVector3_Make(normal.x, +1, +1);
    } else if(normal.y != 0) { // If the normal is along the y-axis.
        sample[0] = GSIntegerVector3_Make(-1, normal.y, -1);
        sample[1] = GSIntegerVector3_Make(-1, normal.y, +1);
        sample[2] = GSIntegerVector3_Make(+1, normal.y, -1);
        sample[3] = GSIntegerVector3_Make(+1, normal.y, +1);
    } else if(normal.z != 0) { // If the normal is along the z-axis.
        sample[0] = GSIntegerVector3_Make(-1, -1, normal.z);
        sample[1] = GSIntegerVector3_Make(-1, +1, normal.z);
        sample[2] = GSIntegerVector3_Make(+1, -1, normal.z);
        sample[3] = GSIntegerVector3_Make(+1, +1, normal.z);
    } else {
        assert(!"expected normal vector to point along one of the eight cardinal directions");
    }
}
