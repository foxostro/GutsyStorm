//
//  GSChunkVoxelData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSChunkVoxelData.h"
#import "GSRay.h"
#import "GSBoxedVector.h"
#import "GSTerrainChunkStore.h"
#import "GSNeighborhood.h"
#import "GSErrorCodes.h"
#import "GSMutableBuffer.h"
#import "GSActivity.h"
#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"
#import "GSTerrainGenerator.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


#define VOXEL_MAGIC ('lxov')
#define VOXEL_VERSION (0)


struct GSChunkVoxelHeader
{
    uint32_t magic;
    uint32_t version;
    uint32_t w, h, d;
    uint64_t len;
};


static void markOutsideVoxelsInColumn(GSVoxel * _Nonnull voxels, GSIntAABB voxelBox,
                                      vector_long3 offsetVoxelBox, vector_long3 column);


@interface GSChunkVoxelData ()

- (BOOL)validateVoxelData:(nonnull NSData *)data error:(NSError **)error;

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data;

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data
                  editPos:(vector_float3)editPos
                 oldBlock:(GSVoxel)oldBlock;

- (nonnull GSTerrainBuffer *)newTerrainBufferWithGenerator:(nonnull GSTerrainGenerator *)generator
                                                   journal:(nonnull GSTerrainJournal *)journal;

@end


@implementation GSChunkVoxelData
{
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
}

@synthesize minP;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}

- (nonnull instancetype)initWithMinP:(vector_float3)mp
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                             journal:(nullable GSTerrainJournal *)journal
                           generator:(nonnull GSTerrainGenerator *)generator
                        allowLoading:(BOOL)allowLoading
{
    NSParameterAssert(groupForSaving);
    NSParameterAssert(queueForSaving);
    NSParameterAssert(generator);
    NSParameterAssert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

    if (self = [super init]) {
        GSStopwatchTraceStep(@"Initializing voxel chunk %@", [GSBoxedVector boxedVectorWithVector:mp]);

        GSTerrainJournal *effectiveJournal = journal;

        minP = mp;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;

        // Load the terrain from disk if possible, else generate it from scratch.
        BOOL failedToLoadFromFile = YES;
        GSTerrainBuffer *buffer = nil;
        NSString *fileName = [GSChunkVoxelData fileNameForVoxelDataFromMinP:minP];
        NSURL *url = folder ? [NSURL URLWithString:fileName relativeToURL:_folder] : nil;
        NSError *error = nil;
        NSData *data = nil;
        
        if (allowLoading && folder) {
            data = [NSData dataWithContentsOfFile:[url path]
                                          options:NSDataReadingMapped
                                            error:&error];
        }
        
        if (!data) {
            if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == 260)) {
                // File not found. We don't have to log this one because it's common and we know how to recover.
                // Since this is a common error simply meaning that the voxel have not yet been generated, don't
                // bother trying to reconstruct the chunk from the journal, i.e. we only use the journal to recover
                // from errors.
                effectiveJournal = nil;
            } else {
                // Squelch the error message if we were explicitly instructed to not load from file.
                if (allowLoading) {
                    NSLog(@"ERROR: Failed to load voxel data for chunk at \"%@\": %@", fileName, error);
                }
            }
        } else if (![self validateVoxelData:data error:&error]) {
             NSLog(@"ERROR: Failed to validate the voxel data file at \"%@\": %@", fileName, error);
        } else {
            const struct GSChunkVoxelHeader * restrict header = [data bytes];
            const void * restrict voxelBytes = ((void *)header) + sizeof(struct GSChunkVoxelHeader);
            buffer = [[GSTerrainBuffer alloc] initWithDimensions:GSChunkSizeIntVec3 copyUnalignedData:voxelBytes];
            failedToLoadFromFile = NO; // success!
            GSStopwatchTraceStep(@"Loaded voxel chunk contents from file.");
        }

        if (failedToLoadFromFile) {
            buffer = [self newTerrainBufferWithGenerator:generator journal:effectiveJournal];
            struct GSChunkVoxelHeader header = {
                .magic = VOXEL_MAGIC,
                .version = VOXEL_VERSION,
                .w = CHUNK_SIZE_X,
                .h = CHUNK_SIZE_Y,
                .d = CHUNK_SIZE_Z,
                .len = (uint64_t)BUFFER_SIZE_IN_BYTES(GSChunkSizeIntVec3)
            };
            
            if (url) {
                [buffer saveToFile:url
                             queue:_queueForSaving
                             group:_groupForSaving
                            header:[NSData dataWithBytes:&header length:sizeof(header)]];
            }

            GSStopwatchTraceStep(@"Generated voxel chunk contents.");
        }
        
        if (!buffer) {
            [NSException raise:NSGenericException format:@"Failed to fetch or generate voxel data at %@", fileName];
        }

        _voxels = buffer;

        GSStopwatchTraceStep(@"Done initializing voxel chunk %@", [GSBoxedVector boxedVectorWithVector:mp]);
    }

    return self;
}

- (nonnull instancetype)initWithMinP:(vector_float3)mp
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                                data:(nonnull GSTerrainBuffer *)data
                             editPos:(vector_float3)editPos
                            oldBlock:(GSVoxel)oldBlock
{
    if (self = [super init]) {
        minP = mp;
        
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        GSMutableBuffer *dataWithUpdatedOutside = [GSMutableBuffer newMutableBufferWithBuffer:data];
        [self markOutsideVoxels:dataWithUpdatedOutside
                        editPos:editPos
                       oldBlock:oldBlock];
        _voxels = dataWithUpdatedOutside;
    }
    
    return self;
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // all voxel data objects are immutable, so return self instead of deep copying
}

- (BOOL)validateVoxelData:(nonnull NSData *)data error:(NSError **)error
{
    NSParameterAssert(data);
    
    const struct GSChunkVoxelHeader *header = [data bytes];
    
    if (!header) {
        if (error) {
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : @"Cannot get pointer to header."}];
        }
        return NO;
    }
    
    if (header->magic != VOXEL_MAGIC) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected magic number in voxel data file: found %d " \
                              @"but expected %d", header->magic, VOXEL_MAGIC];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSBadMagicNumberError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->version != VOXEL_VERSION) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected version number in voxel data file: found %d " \
                              @"but expected %d", header->version, VOXEL_VERSION];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnsupportedVersionError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }

    if ((header->w!=CHUNK_SIZE_X) || (header->h!=CHUNK_SIZE_Y) || (header->d!=CHUNK_SIZE_Z)) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected chunk size used in voxels data: found " \
                              @"(%d,%d,%d) but expected (%d,%d,%d)",
                              header->w, header->h, header->d,
                              CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedChunkDimensionsError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }

    if (header->len != BUFFER_SIZE_IN_BYTES(GSChunkSizeIntVec3)) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected number of bytes in voxel data: found %lu " \
                              @"but expected %zu bytes", (unsigned long)[data length],
                              BUFFER_SIZE_IN_BYTES(GSChunkSizeIntVec3)];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }

    return YES;
}

- (GSVoxel)voxelAtLocalPosition:(vector_long3)p
{
    assert(p.x >= 0 && p.x < CHUNK_SIZE_X);
    assert(p.y >= 0 && p.y < CHUNK_SIZE_Y);
    assert(p.z >= 0 && p.z < CHUNK_SIZE_Z);
    GSTerrainBufferElement value = [_voxels valueAtPosition:p];
    GSVoxel voxel = *((const GSVoxel *)&value);
    return voxel;
}

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data
{
    NSParameterAssert(data);
    
    vector_long3 p;
    GSIntAABB chunkBox = {GSZeroIntVec3, GSChunkSizeIntVec3};

    GSVoxel *voxels = (GSVoxel *)[data mutableData];
    vector_long3 offsetVoxelBox = data.offsetFromChunkLocalSpace;
    GSIntAABB voxelBox = { GSZeroIntVec3, data.dimensions };

    // Determine voxels in the chunk which are outside. That is, voxels directly exposed to the sky from above.
    // We assume here that the chunk is the height of the world.
    FOR_Y_COLUMN_IN_BOX(p, chunkBox)
    {
        markOutsideVoxelsInColumn(voxels, voxelBox, offsetVoxelBox, p);
    }
}

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data
                  editPos:(vector_float3)editPos
                 oldBlock:(GSVoxel)oldBlock
{
    NSParameterAssert(data);
    
    GSVoxel *voxels = (GSVoxel *)[data mutableData];
    GSIntAABB voxelBox = { GSZeroIntVec3, data.dimensions };
    vector_long3 offsetVoxelBox = data.offsetFromChunkLocalSpace;
    vector_long3 editPosLocal = vector_long(editPos - minP);
    vector_long3 columnPos = GSMakeIntegerVector3(editPosLocal.x, 0, editPosLocal.z);
    
    markOutsideVoxelsInColumn(voxels, voxelBox, offsetVoxelBox, columnPos);
}

/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is
 * translated so that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that,
 * for example, the width of the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (nonnull GSTerrainBuffer *)newTerrainBufferWithGenerator:(nonnull GSTerrainGenerator *)generator
                                                   journal:(nonnull GSTerrainJournal *)journal
{
    vector_float3 thisMinP = self.minP;
    vector_long3 p;
    vector_long3 border = (vector_long3){2, 0, 2};
    GSIntAABB chunkBox = { .mins = GSZeroIntVec3, .maxs = GSChunkSizeIntVec3};
    GSIntAABB box = { .mins = chunkBox.mins - border, .maxs = chunkBox.maxs + border};

    const size_t count = (box.maxs.x-box.mins.x) * (box.maxs.y-box.mins.y) * (box.maxs.z-box.mins.z);
    GSVoxel *voxels = malloc(count * sizeof(GSVoxel));

    if (!voxels) {
        [NSException raise:NSMallocException format:@"Out of memory allocating voxels in -newTerrainBufferWithGenerator:."];
    }

    // Generate voxels for the region of the chunk, plus a 1 block wide border.
    // Note that whether the block is outside or not is calculated later.
    [generator generateWithDestination:voxels count:count region:&box offsetToWorld:thisMinP];

    GSMutableBuffer *data;
    
    // Copy the voxels for the chunk to their final destination.
    data = [[GSMutableBuffer alloc] initWithDimensions:GSChunkSizeIntVec3];
    GSVoxel *buf = (GSVoxel *)[data mutableData];

    FOR_Y_COLUMN_IN_BOX(p, chunkBox)
    {
        memcpy(&buf[INDEX_BOX(p, chunkBox)], &voxels[INDEX_BOX(p, box)], chunkBox.maxs.y * sizeof(GSVoxel));
    }

    free(voxels);
    
    // Scan the journal and apply any changes found which affect this chunk.
    if (journal) {
        for(GSTerrainJournalEntry *entry in journal.journalEntries)
        {
            vector_long3 worldPos = [entry.position integerVectorValue];
            vector_long3 localPos = worldPos - vector_long(thisMinP);

            if (localPos.x >= chunkBox.mins.x && localPos.x < chunkBox.maxs.x &&
                localPos.y >= chunkBox.mins.y && localPos.y < chunkBox.maxs.y &&
                localPos.z >= chunkBox.mins.z && localPos.z < chunkBox.maxs.z) {
                buf[INDEX_BOX(localPos, chunkBox)] = entry.value;
            }
        }
    }

    [self markOutsideVoxels:data];

    return data;
}

- (void)saveToFile
{
    if (_folder) {
        NSString *fileName = [GSChunkVoxelData fileNameForVoxelDataFromMinP:self.minP];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
        struct GSChunkVoxelHeader header = {
            .magic = VOXEL_MAGIC,
            .version = VOXEL_VERSION,
            .w = CHUNK_SIZE_X,
            .h = CHUNK_SIZE_Y,
            .d = CHUNK_SIZE_Z,
            .len = (uint64_t)BUFFER_SIZE_IN_BYTES(GSChunkSizeIntVec3)
        };
        [self.voxels saveToFile:url
                          queue:_queueForSaving
                          group:_groupForSaving
                         header:[NSData dataWithBytes:&header length:sizeof(header)]];
    }
}

- (nonnull instancetype)copyWithEditAtPoint:(vector_float3)pos
                                      block:(GSVoxel)newBlock
                                  operation:(GSVoxelBitwiseOp)op
{
    NSParameterAssert(vector_equal(GSMinCornerForChunkAtPoint(pos), minP));
    vector_long3 chunkLocalPos = vector_long(pos-minP);
    GSTerrainBufferElement newValue = *((GSTerrainBufferElement *)&newBlock);
    GSVoxel oldBlock = [self voxelAtLocalPosition:chunkLocalPos];
    GSTerrainBuffer *modified = [self.voxels copyWithEditAtPosition:chunkLocalPos value:newValue operation:op];
    GSChunkVoxelData *modifiedVoxelData = [[[self class] alloc] initWithMinP:minP
                                                                      folder:_folder
                                                              groupForSaving:_groupForSaving
                                                              queueForSaving:_queueForSaving
                                                                        data:modified
                                                                     editPos:pos
                                                                    oldBlock:oldBlock];
    return modifiedVoxelData;
}

- (void)invalidate
{
    NSString *fileName = [[self class] fileNameForVoxelDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end


// For the specified voxel columnm, mark outside voxels and mark the voxel top textures. 
static void markOutsideVoxelsInColumn(GSVoxel * _Nonnull voxels, GSIntAABB voxelBox,
                                      vector_long3 offsetVoxelBox, vector_long3 p)
{
    // Get the y value of the highest non-empty voxel in the chunk.
    GSVoxel highestVoxel;
    int heightOfHighestVoxel;
    for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
    {
        vector_long3 chunkLocalPos = { p.x, heightOfHighestVoxel, p.z };
        vector_long3 q = chunkLocalPos + offsetVoxelBox;
        GSVoxel voxel = voxels[INDEX_BOX(q, voxelBox)];
        
        if(voxel.type != VOXEL_TYPE_EMPTY) {
            highestVoxel = voxel;
            break;
        }
    }
    
    // In order for Marching Squares to work properly on the top face we need to ensure that the top face of the
    // Marching Cubes cell contains the materials we'd see if we looked straight down at the chunk from above.
    // We take the 3D volume of voxel textures and squish / project the texture for the highest voxel in a column
    // onto a 2D plane upon which we run marching squares. The values of 2D plane being represented by having each
    // column in the 3D volume of voxels contain the same value.
    //
    // However, if all voxels in the column do use the same value then we cannot have overlapping Y-levels use
    // different ground textures. To fix this problem, we change the "collapsed value" every time the column
    // transitions between empty and not-empty.
    //
    // In effect, we're going to be running Marching Squares on a collection of planes parallel to the XZ plan, all
    // stacked on top of one another.
    int prevTexTop = highestVoxel.texTop;
    BOOL prevWasEmpty = YES;
    for(p.y = CHUNK_SIZE_Y-1; p.y >= 0; --p.y)
    {
        vector_long3 q = p + offsetVoxelBox;
        GSVoxel *voxel = &voxels[INDEX_BOX(q, voxelBox)];
        voxel->outside = (p.y >= heightOfHighestVoxel);
        
        BOOL isEmpty = voxel->type == VOXEL_TYPE_EMPTY;
        if (isEmpty == prevWasEmpty) {
            voxel->texTop = prevTexTop;
        } else {
            prevTexTop = voxel->texTop;
            prevWasEmpty = isEmpty;
        }
    }
}