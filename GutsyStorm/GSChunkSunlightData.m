//
//  GSChunkSunlightData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSNeighborhood.h"
#import "GSMutableBuffer.h"
#import "GSStopwatch.h"
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
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
}

@synthesize cost;
@synthesize minP;

+ (nonnull NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.sunlight.dat", minP.x, minP.y, minP.z];
}

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                         neighborhood:(nonnull GSNeighborhood *)neighborhood
{
    if(self = [super init]) {
        assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

        minP = minCorner;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _neighborhood = neighborhood;
        _sunlight = [self newSunlightBufferWithNeighborhood:neighborhood folder:folder];
        cost = BUFFER_SIZE_IN_BYTES(sunlightDim);
    }
    return self;
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // GSChunkSunlightData is immutable, so return self instead of deep copying
}

/* Copy the voxel data for the neighborhood into a new buffer and return the buffer. If the method would block when taking the
 * locks on the neighborhood then instead return NULL. The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y
 * elements in size and may be indexed using the INDEX2 macro.
 */
- (nonnull GSVoxel *)newVoxelBufferWithNeighborhood:(nonnull GSNeighborhood *)neighborhood
{
    static const size_t size = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;

    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    GSVoxel *combinedVoxelData = combinedVoxelData = malloc(size*sizeof(GSVoxel));
    if(!combinedVoxelData) {
        [NSException raise:NSMallocException format:@"Failed to allocate memory for combinedVoxelData."];
    }

    static long offsetsX[CHUNK_NUM_NEIGHBORS];
    static long offsetsZ[CHUNK_NUM_NEIGHBORS];
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        for(GSVoxelNeighborIndex i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            offsetsX[i] = offset.x;
            offsetsZ[i] = offset.z;
        }
    });

    [neighborhood enumerateNeighborsWithBlock2:^(GSVoxelNeighborIndex i, GSChunkVoxelData *voxels) {
        const GSVoxel *data = (const GSVoxel *)[voxels.voxels data];
        long offsetX = offsetsX[i];
        long offsetZ = offsetsZ[i];

        vector_long3 p;
        FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
        {
            assert(p.x >= 0 && p.x < GSChunkSizeIntVec3.x);
            assert(p.y >= 0 && p.y < GSChunkSizeIntVec3.y);
            assert(p.z >= 0 && p.z < GSChunkSizeIntVec3.z);

            size_t dstIdx = INDEX_BOX(GSMakeIntegerVector3(p.x+offsetX, p.y, p.z+offsetZ), GSCombinedMinP, GSCombinedMaxP);
            size_t srcIdx = INDEX_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3);

            assert(dstIdx < size);
            assert(srcIdx < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));
            assert(sizeof(combinedVoxelData[0]) == sizeof(data[0]));

            memcpy(&combinedVoxelData[dstIdx], &data[srcIdx], CHUNK_SIZE_Y*sizeof(combinedVoxelData[0]));
        }
    }];

    return combinedVoxelData;
}

- (BOOL)isAdjacentToSunlightAtPoint:(vector_long3)p
                         lightLevel:(int)lightLevel
                  combinedVoxelData:(nonnull GSVoxel *)combinedVoxelData
               combinedSunlightData:(nonnull GSTerrainBufferElement *)combinedSunlightData
{
    for(GSVoxelFace i=0; i<FACE_NUM_FACES; ++i)
    {
        vector_long3 a = p + GSOffsetForVoxelFace[i];

        if(a.x < -CHUNK_SIZE_X || a.x >= (2*CHUNK_SIZE_X) ||
           a.z < -CHUNK_SIZE_Z || a.z >= (2*CHUNK_SIZE_Z) ||
           a.y < 0 || a.y >= CHUNK_SIZE_Y) {
            continue; // The point is out of bounds, so bail out.
        }

        size_t idx = INDEX_BOX(a, GSCombinedMinP, GSCombinedMaxP);

        if(combinedVoxelData[idx].opaque) {
            continue;
        }

        if(combinedSunlightData[idx] == lightLevel) {
            return YES;
        }
    }

    return NO;
}

/* Generate and return  sunlight data for this chunk from the specified voxel data buffer. The voxel data buffer must be
 * (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and should contain voxel data for the entire local
 * neighborhood.
 * The returned sunlight buffer is also this size and may also be indexed using the INDEX_BOX macro. Only the sunlight
 * values for the region of the buffer corresponding to this chunk should be considered to be totally correct.
 * Assumes the caller has already locked the sunlight buffer for reading.
 */
- (nonnull GSTerrainBuffer *)newSunlightBufferUsingCombinedVoxelData:(nonnull GSVoxel *)combinedVoxelData
{
    size_t len = (GSCombinedMaxP.x - GSCombinedMinP.x) * (GSCombinedMaxP.y - GSCombinedMinP.y) * (GSCombinedMaxP.z - GSCombinedMinP.z) * sizeof(GSTerrainBufferElement);
    GSTerrainBufferElement *combinedSunlightData = malloc(len);
    if(!combinedSunlightData) {
        [NSException raise:NSMallocException format:@"Out of memory allocating `combinedSunlightData'."];
    }

    // Initially, set every element in the buffer to CHUNK_LIGHTING_MAX.
    {
        GSTerrainBufferElement pattern[2] = {CHUNK_LIGHTING_MAX, CHUNK_LIGHTING_MAX};
        _Static_assert(sizeof(pattern)==4, "Assumes I can pack two elements into four bytes.");
        memset_pattern4(combinedSunlightData, pattern, len);
    }

    long elevationOfHighestOpaqueBlock = GSCombinedMinP.y;
    vector_long3 p;
    FOR_BOX(p, GSCombinedMinP, GSCombinedMaxP)
    {
        size_t idx = INDEX_BOX(p, GSCombinedMinP, GSCombinedMaxP);
        GSVoxel voxel = combinedVoxelData[idx];
        BOOL directlyLit = (!voxel.opaque) && (voxel.outside);
        combinedSunlightData[idx] = directlyLit ? CHUNK_LIGHTING_MAX : 0;
        
        if (voxel.opaque) {
            elevationOfHighestOpaqueBlock = MAX(elevationOfHighestOpaqueBlock, p.y);
        }
    }
    
    // Every block above the elevation of the highest opaque block will be fully and directly lit.
    // We can take advantage of this to avoid a lot of work.
    vector_long3 maxBoxPoint = GSCombinedMaxP;
    maxBoxPoint.y = elevationOfHighestOpaqueBlock;

    /* Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
     * Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
     * Set the blocks we find to the next lower light level.
     */
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        FOR_BOX(p, GSCombinedMinP, maxBoxPoint)
        {
            size_t idx = INDEX_BOX(p, GSCombinedMinP, GSCombinedMaxP);
            GSVoxel voxel = combinedVoxelData[idx];

            if(voxel.opaque || voxel.outside) {
                continue;
            }

            if([self isAdjacentToSunlightAtPoint:p
                                      lightLevel:lightLevel
                               combinedVoxelData:combinedVoxelData
                            combinedSunlightData:combinedSunlightData]) {
                combinedSunlightData[idx] = MAX(combinedSunlightData[idx], lightLevel - 1);
            }
        }
    }

    // Copy the sunlight data we just calculated into _sunlight. Discard portions that do not overlap with this chunk.
    GSTerrainBuffer *sunlight = [GSTerrainBuffer newBufferFromLargerRawBuffer:combinedSunlightData
                                                                      srcMinP:GSCombinedMinP
                                                                      srcMaxP:GSCombinedMaxP];

    free(combinedSunlightData);

    return sunlight;
}

- (nonnull GSTerrainBuffer *)newSunlightBufferWithNeighborhood:(nonnull GSNeighborhood *)neighborhood
                                                        folder:(nonnull NSURL *)folder
{
    GSTerrainBuffer *buffer = nil;

    BOOL failedToLoadFromFile = YES;
    NSString *fileName = [GSChunkSunlightData fileNameForSunlightDataFromMinP:self.minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:folder];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:[url path]
                                          options:NSDataReadingMapped
                                            error:&error];

    if(data) {
        if (![self validateSunlightData:data error:&error]) {
            NSLog(@"ERROR: Failed to validate the sunlight data file at \"%@\": %@", fileName, error);
        } else {
            const struct GSChunkSunlightHeader * restrict header = [data bytes];
            const void * restrict sunlightBytes = ((void *)header) + sizeof(struct GSChunkSunlightHeader);
            buffer = [[GSTerrainBuffer alloc] initWithDimensions:sunlightDim copyUnalignedData:sunlightBytes];
            failedToLoadFromFile = NO;
        }
    } else if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == 260)) {
        // File not found. We don't have to log this one because it's common and we know how to recover.
    } else {
        NSLog(@"ERROR: Failed to load sunlight data for chunk at \"%@\": %@", fileName, error);
    }
    
    if (failedToLoadFromFile) {
        GSVoxel *data = [self newVoxelBufferWithNeighborhood:neighborhood];
        buffer = [self newSunlightBufferUsingCombinedVoxelData:data];
        free(data);

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
    
    if (!buffer) {
        [NSException raise:NSGenericException
                    format:@"Failed to fetch or generate the sunlight chunk \"%@\"", fileName];
    }

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

@end
