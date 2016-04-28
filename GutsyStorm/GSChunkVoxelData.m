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
#import "GSChunkStore.h"
#import "GSNeighborhood.h"
#import "GSErrorCodes.h"
#import "GSMutableBuffer.h"
#import "GSActivity.h"
#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"


#define VOXEL_MAGIC ('lxov')
#define VOXEL_VERSION (0)


struct GSChunkVoxelHeader
{
    uint32_t magic;
    uint32_t version;
    uint32_t w, h, d;
    uint64_t len;
};


static inline BOOL isExposedToAirOnTop(GSVoxelType voxelType, GSVoxelType typeOfBlockAbove)
{
    return (voxelType!=VOXEL_TYPE_EMPTY         && typeOfBlockAbove==VOXEL_TYPE_EMPTY)          ||
           (voxelType==VOXEL_TYPE_CUBE          && typeOfBlockAbove==VOXEL_TYPE_CORNER_OUTSIDE) ||
           (voxelType==VOXEL_TYPE_CORNER_INSIDE && typeOfBlockAbove==VOXEL_TYPE_CORNER_OUTSIDE) ||
           (voxelType==VOXEL_TYPE_CUBE          && typeOfBlockAbove==VOXEL_TYPE_RAMP);
}


@interface GSChunkVoxelData ()

- (BOOL)validateVoxelData:(nonnull NSData *)data error:(NSError **)error;

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data;

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data
                  editPos:(vector_float3)editPos
                 oldBlock:(GSVoxel)oldBlock;

- (nonnull GSTerrainBuffer *)newTerrainBufferWithGenerator:(nonnull GSTerrainProcessorBlock)generator
                                                   journal:(nonnull GSTerrainJournal *)journal;

@end


@implementation GSChunkVoxelData
{
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
}

@synthesize cost;
@synthesize minP;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.voxels.dat", minP.x, minP.y, minP.z];
}

- (nonnull instancetype)initWithMinP:(vector_float3)mp
                              folder:(nonnull NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                             journal:(nonnull GSTerrainJournal *)journal
                           generator:(nonnull GSTerrainProcessorBlock)generator
{
    NSParameterAssert(CHUNK_LIGHTING_MAX < MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z));

    if (self = [super init]) {
        GSStopwatchTraceStep(@"Initializing voxel chunk %@", [GSBoxedVector boxedVectorWithVector:mp]);

        GSTerrainJournal *effectiveJournal = journal;

        minP = mp;
        cost = BUFFER_SIZE_IN_BYTES(GSChunkSizeIntVec3);

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;

        // Load the terrain from disk if possible, else generate it from scratch.
        BOOL failedToLoadFromFile = YES;
        GSTerrainBuffer *buffer = nil;
        NSString *fileName = [GSChunkVoxelData fileNameForVoxelDataFromMinP:minP];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:[url path]
                                              options:NSDataReadingMapped
                                                error:&error];
        
        if (!data) {
            if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == 260)) {
                // File not found. We don't have to log this one because it's common and we know how to recover.
                // Since this is a common error simply meaning that the voxel have not yet been generated, don't
                // bother trying to reconstruct the chunk from the journal, i.e. we only use the journal to recover
                // from errors.
                effectiveJournal = nil;
            } else {
                NSLog(@"ERROR: Failed to load voxel data for chunk at \"%@\": %@", fileName, error);
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
            [buffer saveToFile:url
                         queue:_queueForSaving
                         group:_groupForSaving
                        header:[NSData dataWithBytes:&header length:sizeof(header)]];
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
                              folder:(nonnull NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                                data:(nonnull GSTerrainBuffer *)data
                             editPos:(vector_float3)editPos
                            oldBlock:(GSVoxel)oldBlock
{
    if (self = [super init]) {
        minP = mp;
        cost = BUFFER_SIZE_IN_BYTES(data.dimensions);
        
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        GSMutableBuffer *dataWithUpdatedOutside = [GSMutableBuffer newMutableBufferWithBuffer:data];
        GSStopwatchTraceStep(@"markOutsideVoxels enter");
        [self markOutsideVoxels:dataWithUpdatedOutside
                        editPos:editPos
                       oldBlock:oldBlock];
        GSStopwatchTraceStep(@"markOutsideVoxels leave");
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
    
    // Determine voxels in the chunk which are outside. That is, voxels which are directly exposed to the sky from above.
    // We assume here that the chunk is the height of the world.
    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
    {
        // Get the y value of the highest non-empty voxel in the chunk.
        long heightOfHighestVoxel;
        for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
        {
            GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:GSMakeIntegerVector3(p.x, heightOfHighestVoxel, p.z)];
            
            if(voxel->opaque) {
                break;
            }
        }
        
        for(p.y = 0; p.y < GSChunkSizeIntVec3.y; ++p.y)
        {
            GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:p];
            voxel->outside = (p.y >= heightOfHighestVoxel);
        }
    }
    
    // Determine voxels in the chunk which are exposed to air on top.
    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
    {
        // Find a voxel which is empty and is directly above a cube voxel.
        p.y = CHUNK_SIZE_Y-1;
        GSVoxelType prevType = ((GSVoxel *)[data pointerToValueAtPosition:p])->type;
        for(p.y = CHUNK_SIZE_Y-2; p.y >= 0; --p.y)
        {
            GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:p];
            voxel->exposedToAirOnTop = isExposedToAirOnTop(voxel->type, prevType);
            prevType = voxel->type;
        }
    }
}

- (void)markOutsideVoxels:(nonnull GSMutableBuffer *)data
                  editPos:(vector_float3)editPos
                 oldBlock:(GSVoxel)oldBlock
{
    NSParameterAssert(data);
    vector_long3 p;
    vector_long3 editPosLocal = GSMakeIntegerVector3(editPos.x - minP.x, editPos.y - minP.y, editPos.z - minP.z);
    
    // If the old block was inside then changing it cannot change the outside-ness of the block or any blocks below it.
    // Outside-ness only changes when there is a change to a block which is outside. For example, adding or removing a
    // block in a cave has no effect on outside-ness of blocks. Adding a block outside can make the blocks below it
    // become inside blocks. Removing a block outside can make blocks beneath it become outside blocks.
    if (!oldBlock.outside) {
        p = editPosLocal;
        p.y = 0;
        
        // Get the y value of the highest non-empty voxel in the chunk.
        long heightOfHighestVoxel;
        for(heightOfHighestVoxel = CHUNK_SIZE_Y-1; heightOfHighestVoxel >= 0; --heightOfHighestVoxel)
        {
            GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:GSMakeIntegerVector3(p.x, heightOfHighestVoxel, p.z)];
            
            if(voxel->opaque) {
                break;
            }
        }
        
        for(p.y = 0; p.y < GSChunkSizeIntVec3.y; ++p.y)
        {
            GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:p];
            voxel->outside = (p.y >= heightOfHighestVoxel);
        }
    }
    
    // Determine voxels in the chunk which are exposed to air on top.
    // We need only updpate the modified block and the block below it.
    for(p = editPosLocal; p.y >= editPosLocal.y - 1; --p.y)
    {
        BOOL exposedToAirOnTop = YES;
        GSVoxel *voxel = (GSVoxel *)[data pointerToValueAtPosition:p];
        
        if (p.y < CHUNK_SIZE_Y-1) {
            vector_long3 aboveP = p;
            aboveP.y = p.y + 1;
            GSVoxelType typeOfBlockAbove = ((GSVoxel *)[data pointerToValueAtPosition:aboveP])->type;
            exposedToAirOnTop = isExposedToAirOnTop(voxel->type, typeOfBlockAbove);
        }
        
        voxel->exposedToAirOnTop = exposedToAirOnTop;
    }
}

/* Computes voxelData which represents the voxel terrain values for the points between minP and maxP. The chunk is
 * translated so that voxelData[0,0,0] corresponds to (minX, minY, minZ). The size of the chunk is unscaled so that,
 * for example, the width of the chunk is equal to maxP-minP. Ditto for the other major axii.
 */
- (nonnull GSTerrainBuffer *)newTerrainBufferWithGenerator:(nonnull GSTerrainProcessorBlock)generator
                                                   journal:(nonnull GSTerrainJournal *)journal
{
    vector_float3 thisMinP = self.minP;
    vector_long3 p, a, b;
    a = GSMakeIntegerVector3(-2, 0, -2);
    b = GSMakeIntegerVector3(GSChunkSizeIntVec3.x+2, GSChunkSizeIntVec3.y, GSChunkSizeIntVec3.z+2);

    const size_t count = (b.x-a.x) * (b.y-a.y) * (b.z-a.z);
    GSVoxel *voxels = malloc(count * sizeof(GSVoxel));

    if (!voxels) {
        [NSException raise:NSMallocException format:@"Out of memory allocating voxels in -newTerrainBufferWithGenerator:."];
    }

    // Generate voxels for the region of the chunk, plus a 1 block wide border.
    // Note that whether the block is outside or not is calculated later.
    generator(count, voxels, a, b, thisMinP);

    GSMutableBuffer *data;
    
    // Copy the voxels for the chunk to their final destination.
    data = [[GSMutableBuffer alloc] initWithDimensions:GSChunkSizeIntVec3];
    GSVoxel *buf = (GSVoxel *)[data mutableData];

    FOR_Y_COLUMN_IN_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)
    {
        memcpy(&buf[INDEX_BOX(p, GSZeroIntVec3, GSChunkSizeIntVec3)],
               &voxels[INDEX_BOX(p, a, b)],
               GSChunkSizeIntVec3.y * sizeof(GSVoxel));
    }

    free(voxels);
    
    // Scan the journal and apply any changes found which affect this chunk.
    if (journal) {
        for(GSTerrainJournalEntry *entry in journal.journalEntries)
        {
            vector_long3 worldPos = [entry.position integerVectorValue];
            vector_long3 localPos = worldPos - GSMakeIntegerVector3(thisMinP.x, thisMinP.y, thisMinP.z);

            if (localPos.x >= 0 && localPos.x < GSChunkSizeIntVec3.x &&
                localPos.y >= 0 && localPos.y < GSChunkSizeIntVec3.y &&
                localPos.z >= 0 && localPos.z < GSChunkSizeIntVec3.z) {
                buf[INDEX_BOX(localPos, GSZeroIntVec3, GSChunkSizeIntVec3)] = entry.value;
            }
        }
    }

    [self markOutsideVoxels:data];

    return data;
}

- (void)saveToFile
{
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

- (nonnull instancetype)copyWithEditAtPoint:(vector_float3)pos block:(GSVoxel)newBlock
{
    GSStopwatchTraceStep(@"copyWithEditAtPoint enter");
    NSParameterAssert(vector_equal(GSMinCornerForChunkAtPoint(pos), minP));
    vector_long3 chunkLocalPos = GSMakeIntegerVector3(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    GSTerrainBufferElement newValue = *((GSTerrainBufferElement *)&newBlock);
    GSVoxel oldBlock = [self voxelAtLocalPosition:chunkLocalPos];
    GSTerrainBuffer *modified = [self.voxels copyWithEditAtPosition:chunkLocalPos value:newValue];
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