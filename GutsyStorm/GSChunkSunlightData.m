//
//  GSChunkSunlightData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSNeighborhood.h"
#import "GSMutableBuffer.h"


static const vector_long3 sunlightDim = {CHUNK_SIZE_X+2, CHUNK_SIZE_Y, CHUNK_SIZE_Z+2};


@implementation GSChunkSunlightData
{
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
    dispatch_queue_t _chunkTaskQueue;
}

@synthesize minP;

+ (NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.sunlight.dat", minP.x, minP.y, minP.z];
}

- (instancetype)initWithMinP:(vector_float3)minCorner
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                neighborhood:(GSNeighborhood *)neighborhood
{
    if(self = [super init]) {
        assert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

        minP = minCorner;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _chunkTaskQueue = chunkTaskQueue; // dispatch queue used for chunk background work
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _neighborhood = neighborhood;
        _sunlight = [self newSunlightBufferWithNeighborhood:neighborhood folder:folder];
    }
    return self;
}

- (void)dealloc
{
    _groupForSaving = NULL;
    _chunkTaskQueue = NULL;
    _queueForSaving = NULL;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // GSChunkSunlightData is immutable, so return self instead of deep copying
}

/* Copy the voxel data for the neighborhood into a new buffer and return the buffer. If the method would block when taking the
 * locks on the neighborhood then instead return NULL. The returned buffer is (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y
 * elements in size and may be indexed using the INDEX2 macro.
 */
- (GSVoxel *)newVoxelBufferWithNeighborhood:(GSNeighborhood *)neighborhood
{
    static const size_t size = (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y;

    // Allocate a buffer large enough to hold a copy of the entire neighborhood's voxels
    GSVoxel *combinedVoxelData = combinedVoxelData = malloc(size*sizeof(GSVoxel));
    if(!combinedVoxelData) {
        [NSException raise:@"Out of Memory" format:@"Failed to allocate memory for combinedVoxelData."];
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
                  combinedVoxelData:(GSVoxel *)combinedVoxelData
               combinedSunlightData:(GSTerrainBufferElement *)combinedSunlightData
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
 * (3*CHUNK_SIZE_X)*(3*CHUNK_SIZE_Z)*CHUNK_SIZE_Y elements in size and should contain voxel data for the entire local neighborhood.
 * The returned sunlight buffer is also this size and may also be indexed using the INDEX2 macro. Only the sunlight values for the
 * region of the buffer corresponding to this chunk should be considered to be totally correct.
 * Assumes the caller has already locked the sunlight buffer for reading.
 */
- (GSTerrainBuffer *)newSunlightBufferUsingCombinedVoxelData:(GSVoxel *)combinedVoxelData
{
    GSTerrainBufferElement *combinedSunlightData = malloc((GSCombinedMaxP.x - GSCombinedMinP.x) *
                                                    (GSCombinedMaxP.y - GSCombinedMinP.y) *
                                                    (GSCombinedMaxP.z - GSCombinedMinP.z) * sizeof(GSTerrainBufferElement));

    vector_long3 p;
    FOR_BOX(p, GSCombinedMinP, GSCombinedMaxP)
    {
        size_t idx = INDEX_BOX(p, GSCombinedMinP, GSCombinedMaxP);
        GSVoxel voxel = combinedVoxelData[idx];
        BOOL directlyLit = (!voxel.opaque) && (voxel.outside);
        combinedSunlightData[idx] = directlyLit ? CHUNK_LIGHTING_MAX : 0;
    }

    /* Find blocks that have not had light propagated to them yet and are directly adjacent to blocks at X light.
     * Repeat for all light levels from CHUNK_LIGHTING_MAX down to 1.
     * Set the blocks we find to the next lower light level.
     */
    for(int lightLevel = CHUNK_LIGHTING_MAX; lightLevel >= 1; --lightLevel)
    {
        FOR_BOX(p, GSCombinedMinP, GSCombinedMaxP)
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

    // Copy the sunlight data we just calculated into _sunlight. Discard non-overlapping portions.
    GSTerrainBuffer *sunlight = [GSTerrainBuffer newBufferFromLargerRawBuffer:combinedSunlightData
                                                                        srcMinP:GSCombinedMinP
                                                                        srcMaxP:GSCombinedMaxP];

    free(combinedSunlightData);

    return sunlight;
}

- (GSTerrainBuffer *)newSunlightBufferWithNeighborhood:(GSNeighborhood *)neighborhood folder:(NSURL *)folder
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
                buffer = [[GSTerrainBuffer alloc] initWithDimensions:sunlightDim data:[data bytes]];
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
