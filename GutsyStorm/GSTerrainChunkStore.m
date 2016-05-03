//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSRay.h"
#import "GSCamera.h"
#import "GSActiveRegion.h"
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


@interface GSTerrainChunkStore ()

+ (nonnull NSURL *)newTerrainCacheFolderURL;

- (void)createGrids;
- (void)setupActiveRegionWithCamera:(nonnull GSCamera *)cam;

@end


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
    GSActiveRegion *_activeRegion;
    vector_float3 _activeRegionExtent; // The active region is specified relative to the camera position.
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

- (void)createGrids
{
    assert(!_chunkStoreHasBeenShutdown);

    _gridVoxelData = [[GSGrid alloc] initWithName:@"gridVoxelData"];
    _gridSunlightData = [[GSGrid alloc] initWithName:@"gridSunlightData"];
    _gridGeometryData = [[GSGrid alloc] initWithName:@"gridGeometryData"];
    _gridVAO = [[GSGrid alloc] initWithName:@"gridVAO"];
}

- (void)setupActiveRegionWithCamera:(nonnull GSCamera *)cam
{
    assert(!_chunkStoreHasBeenShutdown);
    NSParameterAssert(cam);

    // Active region is bounded at y>=0.
    const NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
    _activeRegionExtent = vector_make(w, CHUNK_SIZE_Y, w);
    _activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:_activeRegionExtent camera:cam chunkStore:self];
}

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                                 camera:(nonnull GSCamera *)camera
                          terrainShader:(nonnull GSShader *)terrainShader
                              glContext:(nonnull NSOpenGLContext *)glContext
                              generator:(nonnull GSTerrainGenerator *)generator
{
    if (self = [super init]) {
        _folder = [GSTerrainChunkStore newTerrainCacheFolderURL];
        _groupForSaving = dispatch_group_create();
        _chunkStoreHasBeenShutdown = NO;
        _camera = camera;
        _terrainShader = terrainShader;
        _glContext = glContext;
        _generator = generator;
        _journal = journal;
        _queueForSaving = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);

        [self createGrids];
        [self setupActiveRegionWithCamera:camera];
        
        // If the cache folder is empty then apply the journal to rebuild it.
        // Since rebuilding from the journal is expensive, we avoid doing unless we have no choice.
        // Also, this provides a pretty easy way for the user to force a rebuild when they need it.
        NSArray *cacheContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[_folder path] error:nil];
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

    // Shutdown the active region, which maintains it's own queue of async updates.
    [_activeRegion shutdown];
    _activeRegion = nil;

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

- (void)drawActiveChunks
{
    assert(_terrainShader);
    assert(_activeRegion);

    matrix_float4x4 translation = GSMatrixFromTranslation(vector_make(0.5f, 0.5f, 0.5f));
    matrix_float4x4 modelView = matrix_multiply(translation, _camera.modelViewMatrix);
    matrix_float4x4 mvp = matrix_multiply(modelView, _camera.projectionMatrix);

    [_terrainShader bind];
    [_terrainShader bindUniformWithMatrix4x4:mvp name:@"mvp"];
    [_activeRegion draw];
    [_terrainShader unbind];
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_activeRegion);
    [_activeRegion updateWithCameraModifiedFlags:flags];
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
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
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
    NSParameterAssert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridSunlightData);
    
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
    NSParameterAssert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridVoxelData);
    
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

+ (nonnull NSURL *)newTerrainCacheFolderURL
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];

    folder = [folder stringByAppendingPathComponent:bundleIdentifier];
    folder = [folder stringByAppendingPathComponent:@"terrain-cache"];
    NSLog(@"ChunkStore will cache terrain data in folder: %@", folder);
    
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        NSLog(@"Failed to create terrain cache folder: %@", folder);
    }
    
    NSURL *url = [[NSURL alloc] initFileURLWithPath:folder isDirectory:YES];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSLog(@"ChunkStore's terrain cache folder is not reachable: %@", folder);
    }
    
    return url;
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
            [_activeRegion clearDrawList];
            break;
    }
}

- (void)printInfo
{
    NSLog(@"Chunk Store:\n\t%@\n\t%@\n\t%@\n\t%@", _gridVoxelData, _gridSunlightData, _gridGeometryData, _gridVAO);
}

@end