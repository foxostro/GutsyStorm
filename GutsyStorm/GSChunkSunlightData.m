//
//  GSChunkSunlightData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSVoxelNeighborhood.h"
#import "GSMutableBuffer.h"
#import "GSActivity.h"
#import "GSErrorCodes.h"


#define SUNLIGHT_MAGIC ('etil')
#define SUNLIGHT_VERSION (0)


struct GSChunkSunlightHeader
{
    uint32_t magic;
    uint32_t version;
    uint32_t w, h, d;
    uint64_t lightMax;
    uint64_t len;
};


static const vector_long3 sunlightDim = {CHUNK_SIZE_X+2, CHUNK_SIZE_Y, CHUNK_SIZE_Z+2};


@implementation GSChunkSunlightData
{
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
}

@synthesize minP;

+ (nonnull NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.sunlight.dat", minP.x, minP.y, minP.z];
}

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood
                        allowLoading:(BOOL)allowLoading
{
    NSParameterAssert(groupForSaving);
    NSParameterAssert(queueForSaving);
    NSParameterAssert(neighborhood);
    assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

    if(self = [super init]) {
        minP = minCorner;
        _folder = folder;
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _neighborhood = neighborhood;
        _sunlight = [self newSunlightBufferWithNeighborhood:neighborhood folder:folder allowLoading:allowLoading];
    }
    return self;
}

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        sunlightData:(nonnull GSTerrainBuffer *)updatedSunlightData
                        neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood
{
    NSParameterAssert(groupForSaving);
    NSParameterAssert(queueForSaving);
    NSParameterAssert(neighborhood);
    NSParameterAssert(updatedSunlightData.dimensions.x == sunlightDim.x);
    NSParameterAssert(updatedSunlightData.dimensions.y == sunlightDim.y);
    NSParameterAssert(updatedSunlightData.dimensions.z == sunlightDim.z);
    NSParameterAssert(updatedSunlightData.offsetFromChunkLocalSpace.x == 1);
    NSParameterAssert(updatedSunlightData.offsetFromChunkLocalSpace.y == 0);
    NSParameterAssert(updatedSunlightData.offsetFromChunkLocalSpace.z == 1);
    assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

    if(self = [super init]) {
        minP = minCorner;
        _folder = folder;
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _neighborhood = neighborhood;
        _sunlight = updatedSunlightData;

        if (folder) {
            NSString *fileName = [[self class] fileNameForSunlightDataFromMinP:self.minP];
            NSURL *url = [NSURL URLWithString:fileName relativeToURL:folder];
            [self saveSunlightBuffer:_sunlight toURL:url];
        }
    }
    return self;
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // GSChunkSunlightData is immutable, so return self instead of deep copying
}

- (nonnull instancetype)copyReplacingSunlightData:(nonnull GSTerrainBuffer *)updatedSunlightData
                                     neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood
{
    NSParameterAssert(updatedSunlightData);
    NSParameterAssert(neighborhood);
    return [[[self class] alloc] initWithMinP:self.minP
                                       folder:_folder
                               groupForSaving:_groupForSaving
                               queueForSaving:_queueForSaving
                                 sunlightData:updatedSunlightData
                                 neighborhood:neighborhood];
}

- (void)saveSunlightBuffer:(nonnull GSTerrainBuffer *)buffer toURL:(nonnull NSURL *)url
{
    NSParameterAssert(buffer);
    NSParameterAssert(url);
    NSParameterAssert([url isFileURL]);

    struct GSChunkSunlightHeader header = {
        .magic = SUNLIGHT_MAGIC,
        .version = SUNLIGHT_VERSION,
        .w = (uint32_t)sunlightDim.x,
        .h = (uint32_t)sunlightDim.y,
        .d = (uint32_t)sunlightDim.z,
        .lightMax = CHUNK_LIGHTING_MAX,
        .len = (uint64_t)BUFFER_SIZE_IN_BYTES(sunlightDim)
    };
    
    [buffer saveToFile:url
                 queue:_queueForSaving
                 group:_groupForSaving
                header:[NSData dataWithBytes:&header length:sizeof(header)]];
}

- (nonnull GSTerrainBuffer *)newSunlightBufferWithNeighborhood:(nonnull GSVoxelNeighborhood *)neighborhood
                                                        folder:(nullable NSURL *)folder
                                                  allowLoading:(BOOL)allowLoading
{
    NSParameterAssert(neighborhood);

    GSStopwatchTraceStep(@"newSunlightBufferWithNeighborhood enter");

    GSTerrainBuffer *buffer = nil;

    BOOL failedToLoadFromFile = YES;
    NSString *fileName = [[self class] fileNameForSunlightDataFromMinP:self.minP];
    NSURL *url = folder ? [NSURL URLWithString:fileName relativeToURL:folder] : nil;
    NSError *error = nil;
    NSData *data = nil;
    
    if (allowLoading && folder) {
        data = [NSData dataWithContentsOfFile:[url path]
                                      options:NSDataReadingMapped
                                        error:&error];
    }

    if(data) {
        if (![self validateSunlightData:data error:&error]) {
            NSLog(@"ERROR: Failed to validate the sunlight data file at \"%@\": %@", fileName, error);
        } else {
            const struct GSChunkSunlightHeader * restrict header = [data bytes];
            const void * restrict sunlightBytes = ((void *)header) + sizeof(struct GSChunkSunlightHeader);
            buffer = [[GSTerrainBuffer alloc] initWithDimensions:sunlightDim copyUnalignedData:sunlightBytes];
            failedToLoadFromFile = NO;
            GSStopwatchTraceStep(@"Loaded sunlight data for chunk from file.");
        }
    } else if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == 260)) {
        // File not found. We don't have to log this one because it's common and we know how to recover.
    } else {
        // Squelch the error message if we were explicitly instructed to not load from file.
        if (allowLoading) {
            NSLog(@"ERROR: Failed to load sunlight data for chunk at \"%@\": %@", fileName, error);
        }
    }

    if (failedToLoadFromFile) {
        buffer = [neighborhood newSunlightBuffer];

        assert(buffer.dimensions.x == sunlightDim.x);
        assert(buffer.dimensions.y == sunlightDim.y);
        assert(buffer.dimensions.z == sunlightDim.z);
        assert(buffer.offsetFromChunkLocalSpace.x == 1);
        assert(buffer.offsetFromChunkLocalSpace.y == 0);
        assert(buffer.offsetFromChunkLocalSpace.z == 1);

        if (url) {
            [self saveSunlightBuffer:buffer toURL:url];
        }
        GSStopwatchTraceStep(@"Generated sunlight data for chunk.");
    }

    if (!buffer) {
        [NSException raise:NSGenericException
                    format:@"Failed to fetch or generate the sunlight chunk \"%@\"", fileName];
    }
    
    GSStopwatchTraceStep(@"newSunlightBufferWithNeighborhood exit");
    return buffer;
}

- (BOOL)validateSunlightData:(nonnull NSData *)data error:(NSError **)error
{
    NSParameterAssert(data);
    
    const struct GSChunkSunlightHeader *header = [data bytes];
    
    if (!header) {
        if (error) {
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : @"Cannot get pointer to header."}];
        }
        return NO;
    }
    
    if (header->magic != SUNLIGHT_MAGIC) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected magic number in sunlight data file: found %d " \
                              @"but expected %d", header->magic, SUNLIGHT_MAGIC];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSBadMagicNumberError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->version != SUNLIGHT_VERSION) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected version number in sunlight data file: found %d " \
                              @"but expected %d", header->version, SUNLIGHT_VERSION];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnsupportedVersionError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->lightMax != CHUNK_LIGHTING_MAX) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected number of light levels found in sunlight data" \
                              @"file: found %llu but expected %d", header->lightMax, CHUNK_LIGHTING_MAX];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSBadValueError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if ((header->w!=sunlightDim.x) || (header->h!=sunlightDim.y) || (header->d!=sunlightDim.z)) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected chunk size used in sunlight data: found " \
                              @"(%d,%d,%d) but expected (%ld,%ld,%ld)",
                              header->w, header->h, header->d,
                              sunlightDim.x, sunlightDim.y, sunlightDim.z];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedChunkDimensionsError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->len != BUFFER_SIZE_IN_BYTES(sunlightDim)) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected number of bytes in sunlight data: found %llu " \
                              @"but expected %zu bytes", header->len, BUFFER_SIZE_IN_BYTES(sunlightDim)];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    return YES;
}

- (void)invalidate
{
    NSString *fileName = [[self class] fileNameForSunlightDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end
