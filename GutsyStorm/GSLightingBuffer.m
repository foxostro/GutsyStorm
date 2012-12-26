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


static inline unsigned averageLightValue(unsigned a, unsigned b, unsigned c, unsigned d)
{
    return (a+b+c+d) >> 2;
}


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

- (void)interpolateLightAtPoint:(GSIntegerVector3)chunkLocalPos outLighting:(block_lighting_t *)lighting
{
    /* Front is in the -Z direction and back is the +Z direction.
     * This is a totally arbitrary convention.
     */
    
    assert(lightingBuffer);
    assert(lighting);
    assert(chunkLocalPos.x >= 0 && chunkLocalPos.x < CHUNK_SIZE_X);
    assert(chunkLocalPos.y >= 0 && chunkLocalPos.y < CHUNK_SIZE_Y);
    assert(chunkLocalPos.z >= 0 && chunkLocalPos.z < CHUNK_SIZE_Z);
    
#define SAMPLE(x, y, z) (samples[(x+1)*3*3 + (y+1)*3 + (z+1)])
    
    unsigned samples[3*3*3];
    
    for(ssize_t x = -1; x <= 1; ++x)
    {
        for(ssize_t y = -1; y <= 1; ++y)
        {
            for(ssize_t z = -1; z <= 1; ++z)
            {
                SAMPLE(x, y, z) = [self lightAtPoint:GSIntegerVector3_Add(chunkLocalPos, GSIntegerVector3_Make(x, y, z))];
            }
        }
    }
    
    lighting->face[FACE_TOP] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE( 0, 1,  0),
                                                                                  SAMPLE( 0, 1, -1),
                                                                                  SAMPLE(-1, 1,  0),
                                                                                  SAMPLE(-1, 1, -1)),
                                                                averageLightValue(SAMPLE( 0, 1,  0),
                                                                                  SAMPLE( 0, 1, +1),
                                                                                  SAMPLE(-1, 1,  0),
                                                                                  SAMPLE(-1, 1, +1)),
                                                                averageLightValue(SAMPLE( 0, 1,  0),
                                                                                  SAMPLE( 0, 1, +1),
                                                                                  SAMPLE(+1, 1,  0),
                                                                                  SAMPLE(+1, 1, +1)),
                                                                averageLightValue(SAMPLE( 0, 1,  0),
                                                                                  SAMPLE( 0, 1, -1),
                                                                                  SAMPLE(+1, 1,  0),
                                                                                  SAMPLE(+1, 1, -1)));
    
    lighting->face[FACE_BOTTOM] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE( 0, -1,  0),
                                                                                     SAMPLE( 0, -1, -1),
                                                                                     SAMPLE(-1, -1,  0),
                                                                                     SAMPLE(-1, -1, -1)),
                                                                   averageLightValue(SAMPLE( 0, -1,  0),
                                                                                     SAMPLE( 0, -1, -1),
                                                                                     SAMPLE(+1, -1,  0),
                                                                                     SAMPLE(+1, -1, -1)),
                                                                   averageLightValue(SAMPLE( 0, -1,  0),
                                                                                     SAMPLE( 0, -1, +1),
                                                                                     SAMPLE(+1, -1,  0),
                                                                                     SAMPLE(+1, -1, +1)),
                                                                   averageLightValue(SAMPLE( 0, -1,  0),
                                                                                     SAMPLE( 0, -1, +1),
                                                                                     SAMPLE(-1, -1,  0),
                                                                                     SAMPLE(-1, -1, +1)));
    
    lighting->face[FACE_BACK] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE( 0, -1, 1),
                                                                                   SAMPLE( 0,  0, 1),
                                                                                   SAMPLE(-1, -1, 1),
                                                                                   SAMPLE(-1,  0, 1)),
                                                                 averageLightValue(SAMPLE( 0, -1, 1),
                                                                                   SAMPLE( 0,  0, 1),
                                                                                   SAMPLE(+1, -1, 1),
                                                                                   SAMPLE(+1,  0, 1)),
                                                                 averageLightValue(SAMPLE( 0, +1, 1),
                                                                                   SAMPLE( 0,  0, 1),
                                                                                   SAMPLE(+1, +1, 1),
                                                                                   SAMPLE(+1,  0, 1)),
                                                                 averageLightValue(SAMPLE( 0, +1, 1),
                                                                                   SAMPLE( 0,  0, 1),
                                                                                   SAMPLE(-1, +1, 1),
                                                                                   SAMPLE(-1,  0, 1)));
    
    lighting->face[FACE_FRONT] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE( 0, -1, -1),
                                                                                    SAMPLE( 0,  0, -1),
                                                                                    SAMPLE(-1, -1, -1),
                                                                                    SAMPLE(-1,  0, -1)),
                                                                  averageLightValue(SAMPLE( 0, +1, -1),
                                                                                    SAMPLE( 0,  0, -1),
                                                                                    SAMPLE(-1, +1, -1),
                                                                                    SAMPLE(-1,  0, -1)),
                                                                  averageLightValue(SAMPLE( 0, +1, -1),
                                                                                    SAMPLE( 0,  0, -1),
                                                                                    SAMPLE(+1, +1, -1),
                                                                                    SAMPLE(+1,  0, -1)),
                                                                  averageLightValue(SAMPLE( 0, -1, -1),
                                                                                    SAMPLE( 0,  0, -1),
                                                                                    SAMPLE(+1, -1, -1),
                                                                                    SAMPLE(+1,  0, -1)));
    
    lighting->face[FACE_RIGHT] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE(+1,  0,  0),
                                                                                    SAMPLE(+1,  0, -1),
                                                                                    SAMPLE(+1, -1,  0),
                                                                                    SAMPLE(+1, -1, -1)),
                                                                  averageLightValue(SAMPLE(+1,  0,  0),
                                                                                    SAMPLE(+1,  0, -1),
                                                                                    SAMPLE(+1, +1,  0),
                                                                                    SAMPLE(+1, +1, -1)),
                                                                  averageLightValue(SAMPLE(+1,  0,  0),
                                                                                    SAMPLE(+1,  0, +1),
                                                                                    SAMPLE(+1, +1,  0),
                                                                                    SAMPLE(+1, +1, +1)),
                                                                  averageLightValue(SAMPLE(+1,  0,  0),
                                                                                    SAMPLE(+1,  0, +1),
                                                                                    SAMPLE(+1, -1,  0),
                                                                                    SAMPLE(+1, -1, +1)));
    
    lighting->face[FACE_LEFT] = packBlockLightingValuesForVertex(averageLightValue(SAMPLE(-1,  0,  0),
                                                                                   SAMPLE(-1,  0, -1),
                                                                                   SAMPLE(-1, -1,  0),
                                                                                   SAMPLE(-1, -1, -1)),
                                                                 averageLightValue(SAMPLE(-1,  0,  0),
                                                                                   SAMPLE(-1,  0, +1),
                                                                                   SAMPLE(-1, -1,  0),
                                                                                   SAMPLE(-1, -1, +1)),
                                                                 averageLightValue(SAMPLE(-1,  0,  0),
                                                                                   SAMPLE(-1,  0, +1),
                                                                                   SAMPLE(-1, +1,  0),
                                                                                   SAMPLE(-1, +1, +1)),
                                                                 averageLightValue(SAMPLE(-1,  0,  0),
                                                                                   SAMPLE(-1,  0, -1),
                                                                                   SAMPLE(-1, +1,  0),
                                                                                   SAMPLE(-1, +1, -1)));
    
#undef SAMPLE
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
