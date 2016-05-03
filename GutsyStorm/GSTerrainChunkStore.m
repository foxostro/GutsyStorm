//
//  GSTerrainChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSRay.h"
#import "GSCamera.h"
#import "GSShader.h"
#import "GSTerrainChunkStore.h"
#import "GSBoxedVector.h"
#import "GSNeighborhood.h"
#import "GSChunkVAO.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSGrid.h"
#import "GSMatrixUtils.h"
#import "GSActivity.h"
#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"
#import "GSReaderWriterLock.h"
#import "GSGridSlot.h"
#import "GSTerrainGenerator.h"
#import "GSTerrainModifyBlockOperation.h"

#import <OpenGL/gl.h>


@implementation GSTerrainChunkStore
{
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
    BOOL _chunkStoreHasBeenShutdown;
    GSCamera *_camera;
    NSURL *_folder;
    GSShader *_terrainShader;
    NSOpenGLContext *_glContext;
    GSTerrainJournal *_journal;
    GSTerrainGenerator *_generator;
}

- (nonnull GSChunkVoxelData *)newVoxelChunkAtPoint:(vector_float3)pos
{
    vector_float3 minCorner = GSMinCornerForChunkAtPoint(pos);
    return [[GSChunkVoxelData alloc] initWithMinP:minCorner
                                           folder:_folder
                                   groupForSaving:_groupForSaving
                                   queueForSaving:_queueForSaving
                                          journal:_journal
                                        generator:_generator];
}

- (nonnull GSChunkSunlightData *)newSunlightChunkAtPoint:(vector_float3)pos
{
    vector_float3 minCorner = GSMinCornerForChunkAtPoint(pos);

    GSNeighborhood *neighborhood = [[GSNeighborhood alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 a = pos + [GSNeighborhood offsetForNeighborIndex:i];
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:a];
        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }

    return [[GSChunkSunlightData alloc] initWithMinP:minCorner
                                              folder:_folder
                                      groupForSaving:_groupForSaving
                                      queueForSaving:_queueForSaving
                                        neighborhood:neighborhood];
}

- (nonnull GSChunkGeometryData *)newGeometryChunkAtPoint:(vector_float3)pos
{
    vector_float3 minCorner = GSMinCornerForChunkAtPoint(pos);
    GSChunkSunlightData *sunlight = [self chunkSunlightAtPoint:minCorner];
    return [[GSChunkGeometryData alloc] initWithMinP:minCorner
                                              folder:_folder
                                            sunlight:sunlight
                                      groupForSaving:_groupForSaving
                                      queueForSaving:_queueForSaving
                                        allowLoading:YES];
}

- (nonnull GSChunkVAO *)newVAOChunkAtPoint:(vector_float3)pos
{
    vector_float3 minCorner = GSMinCornerForChunkAtPoint(pos);
    GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:minCorner];
    return [[GSChunkVAO alloc] initWithChunkGeometry:geometry
                                           glContext:_glContext];
}

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                            cacheFolder:(nonnull NSURL *)url
                                 camera:(nonnull GSCamera *)camera
                              glContext:(nonnull NSOpenGLContext *)glContext
                              generator:(nonnull GSTerrainGenerator *)generator
{
    if (self = [super init]) {
        _folder = url;
        _groupForSaving = dispatch_group_create();
        _chunkStoreHasBeenShutdown = NO;
        _camera = camera;
        _glContext = glContext;
        _generator = generator;
        _journal = journal;
        _queueForSaving = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);

        _gridVoxelData = [[GSGrid alloc] initWithName:@"gridVoxelData"];
        _gridSunlightData = [[GSGrid alloc] initWithName:@"gridSunlightData"];
        _gridGeometryData = [[GSGrid alloc] initWithName:@"gridGeometryData"];
        _gridVAO = [[GSGrid alloc] initWithName:@"gridVAO"];
        
        // If the cache folder is empty then apply the journal to rebuild it.
        // Since rebuilding from the journal is expensive, we avoid doing unless we have no choice.
        // Also, this provides a pretty easy way for the user to force a rebuild when they need it.
        NSArray *cacheContents = nil;
        if (_folder) {
            cacheContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[_folder path] error:nil];
        }
        if (!cacheContents || cacheContents.count == 0) {
            [self applyJournal:journal];
        }
    }
    
    return self;
}

- (void)shutdown
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridVoxelData);
    assert(_gridSunlightData);
    assert(_gridGeometryData);
    assert(_gridVAO);
    assert(_groupForSaving);
    assert(_queueForSaving);

    // Wait for save operations to complete.
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(_groupForSaving, DISPATCH_TIME_FOREVER);
    NSLog(@"All chunks have been saved.");
    
    // From this point on, we do not expect anyone to access the chunk store data.
    _chunkStoreHasBeenShutdown = YES;
    
    [_gridVoxelData evictAllItems];
    _gridVoxelData = nil;

    [_gridSunlightData evictAllItems];
    _gridSunlightData = nil;

    [_gridGeometryData evictAllItems];
    _gridGeometryData = nil;

    [_gridVAO evictAllItems];
    _gridVAO = nil;

    _groupForSaving = NULL;
    _queueForSaving = NULL;
}

- (void)applyJournal:(nonnull GSTerrainJournal *)journal
{
    // XXX: Should applyJournal even be a part of GSTerrainChunkStore?
    NSParameterAssert(journal);

    assert(!_chunkStoreHasBeenShutdown);
    
    GSStopwatchTraceBegin(@"applyJournal");
    
    for(GSTerrainJournalEntry *entry in journal.journalEntries)
    {
        GSTerrainModifyBlockOperation *op;
        op = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:self
                                                                 block:entry.value
                                                              position:[entry.position vectorValue]
                                                               journal:nil];
        [op main];
    }

    dispatch_group_wait(_groupForSaving, DISPATCH_TIME_FOREVER);
    GSStopwatchTraceEnd(@"applyJournal");
}

- (nullable GSChunkVAO *)tryToGetVaoAtPoint:(vector_float3)pos
{
    if (_chunkStoreHasBeenShutdown) {
        return nil;
    }

    GSGridSlot *slot = [_gridVAO slotAtPoint:pos blocking:NO];
    
    if (!(slot && [slot.lock tryLockForReading])) {
        return nil;
    }
    
    GSChunkVAO *vao = (GSChunkVAO *)slot.item;
    
    [slot.lock unlockForReading];
    
    return vao;
}

- (nullable GSChunkVAO *)nonBlockingVaoAtPoint:(GSBoxedVector *)pos createIfMissing:(BOOL)createIfMissing
{
    if (_chunkStoreHasBeenShutdown) {
        return nil;
    }
    
    vector_float3 p = [pos vectorValue];
    GSGridSlot *slot = [_gridVAO slotAtPoint:p blocking:NO];
    
    if (!(slot && [slot.lock tryLockForWriting])) {
        return nil;
    }
    
    GSChunkVAO *vao = (GSChunkVAO *)slot.item;
    
    if (!vao) {
        vao = [self newVAOChunkAtPoint:p];
        slot.item = vao;
    }
    
    [slot.lock unlockForWriting];
    
    return vao;
}

- (nonnull GSChunkGeometryData *)chunkGeometryAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridGeometryData);

    GSChunkGeometryData *geo = nil;
    GSGridSlot *slot = [_gridGeometryData slotAtPoint:p];

    [slot.lock lockForWriting];
    if (slot.item) {
        geo = (GSChunkGeometryData *)slot.item;
    } else {
        geo = [self newGeometryChunkAtPoint:p];
        slot.item = geo;
    }
    [slot.lock unlockForWriting];

    return geo;
}

- (nonnull GSChunkSunlightData *)chunkSunlightAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    
    GSChunkSunlightData *sunlight = nil;
    GSGridSlot *slot = [_gridSunlightData slotAtPoint:p];
    
    [slot.lock lockForWriting];
    if (slot.item) {
        sunlight = (GSChunkSunlightData *)slot.item;
    } else {
        sunlight = [self newSunlightChunkAtPoint:p];
        slot.item = sunlight;
    }
    [slot.lock unlockForWriting];
    
    return sunlight;
}

- (nonnull GSChunkVoxelData *)chunkVoxelsAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    
    GSChunkVoxelData *voxels = nil;
    GSGridSlot *slot = [_gridVoxelData slotAtPoint:p];
    
    [slot.lock lockForWriting];
    if (slot.item) {
        voxels = (GSChunkVoxelData *)slot.item;
    } else {
        voxels = [self newVoxelChunkAtPoint:p];
        slot.item = voxels;
    }
    [slot.lock unlockForWriting];
    
    return voxels;
}

- (void)memoryPressure:(dispatch_source_memorypressure_flags_t)status
{
    if (_chunkStoreHasBeenShutdown) {
        return;
    }

    switch(status)
    {
        case DISPATCH_MEMORYPRESSURE_NORMAL:
            _gridVoxelData.countLimit = 0;
            _gridSunlightData.countLimit = 0;
            _gridGeometryData.countLimit = 0;
            _gridVAO.countLimit = 0;
            break;
            
        case DISPATCH_MEMORYPRESSURE_WARN:
            _gridVoxelData.countLimit = _gridVoxelData.count;
            _gridSunlightData.countLimit = _gridSunlightData.count;
            _gridGeometryData.countLimit = _gridGeometryData.count;
            _gridVAO.countLimit = _gridVAO.count;
            break;
            
        case DISPATCH_MEMORYPRESSURE_CRITICAL:
            _gridVoxelData.countLimit = _gridVoxelData.count;
            _gridSunlightData.countLimit = _gridSunlightData.count;
            _gridGeometryData.countLimit = _gridGeometryData.count;
            _gridVAO.countLimit = _gridVAO.count;
            
            [_gridVoxelData evictAllItems];
            [_gridSunlightData evictAllItems];
            [_gridGeometryData evictAllItems];
            [_gridVAO evictAllItems];
            break;
    }
}

- (void)printInfo
{
    NSLog(@"Chunk Store:\n\t%@\n\t%@\n\t%@\n\t%@", _gridVoxelData, _gridSunlightData, _gridGeometryData, _gridVAO);
}

@end