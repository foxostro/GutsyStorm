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

    @autoreleasepool {
        BOOL failedToLoadFromFile = YES;
        NSString *fileName = [GSChunkSunlightData fileNameForSunlightDataFromMinP:self.minP];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:folder];
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:[url path]
                                              options:NSDataReadingMapped
                                                error:&error];

        if(data) {
            if ([data length] != BUFFER_SIZE_IN_BYTES(sunlightDim)) {
                NSLog(@"unexpected number of bytes in sunlight file \"%@\": found %lu but expected %zu bytes",
                      fileName, (unsigned long)[data length], BUFFER_SIZE_IN_BYTES(sunlightDim));
            } else {
                buffer = [[GSTerrainBuffer alloc] initWithDimensions:sunlightDim cloneAlignedData:[data bytes]];
                failedToLoadFromFile = NO;
            }
        }
        
        if (failedToLoadFromFile) {
            GSVoxel *data = [self newVoxelBufferWithNeighborhood:neighborhood];
            buffer = [self newSunlightBufferUsingCombinedVoxelData:data];
            free(data);
            [buffer saveToFile:url queue:_queueForSaving group:_groupForSaving];
        }

        assert(buffer);
    }

    return buffer;
}

@end
