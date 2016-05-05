//
//  GSTerrainModifyBlockOperation.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/2/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainModifyBlockOperation.h"
#import "GSTerrainChunkStore.h"
#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"
#import "GSGridSlot.h"
#import "GSGrid.h"
#import "GSBoxedVector.h"
#import "GSActivity.h"
#import "GSChunkVAO.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSSunlightNeighborhood.h"


#define ARRAY_LEN(a) (sizeof(a)/sizeof(a[0]))


@implementation GSTerrainModifyBlockOperation
{
    GSTerrainChunkStore *_chunkStore;
    GSVoxel _block;
    vector_float3 _pos;
    GSTerrainJournal *_journal;
}

- (nonnull instancetype)init NS_UNAVAILABLE
{
    @throw nil;
}

- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
                                     block:(GSVoxel)block
                                  position:(vector_float3)pos
                                   journal:(nullable GSTerrainJournal *)journal
{
    if (self = [super init]) {
        _chunkStore = chunkStore;
        _block = block;
        _pos = pos;
        _journal = journal;
    }
    return self;
}

- (void)updateVoxelsWithVoxelSlots:(nonnull GSNeighborhood<GSGridSlot *> *)voxSlots
                    originalVoxels:(GSChunkVoxelData * _Nonnull * _Nonnull)voxels1
                 replacementVoxels:(GSChunkVoxelData * _Nonnull * _Nonnull)voxels2
{
    NSParameterAssert(voxSlots);
    NSParameterAssert(voxels1);
    NSParameterAssert(voxels2);

    GSGridSlot *voxSlot = [voxSlots neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    *voxels1 = (GSChunkVoxelData *)voxSlot.item;
    if (!*voxels1) {
        *voxels1 = [_chunkStore newVoxelChunkAtPoint:_pos];
    }
    [*voxels1 invalidate];
    *voxels2 = [*voxels1 copyWithEditAtPoint:_pos block:_block];
    [*voxels2 saveToFile];
    voxSlot.item = *voxels2;

    GSStopwatchTraceStep(@"Updated voxels.");
}

- (GSTerrainBuffer *)updateSunlightWithSunSlots:(nonnull GSNeighborhood<GSGridSlot *> *)sunSlots
                                 originalVoxels:(nonnull GSChunkVoxelData *)voxels1
                              replacementVoxels:(nonnull GSChunkVoxelData *)voxels2
                               affectedAreaMinP:(vector_long3 * _Nullable)affectedAreaMinP
                               affectedAreaMaxP:(vector_long3 * _Nullable)affectedAreaMaxP
{
    GSTerrainBuffer *nSunlight = nil;
    
    GSGridSlot *sunSlot = [sunSlots neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    GSChunkSunlightData *sunlight = (GSChunkSunlightData *)sunSlot.item;
    
    if (!sunlight) {
        GSStopwatchTraceStep(@"Skipping sunlight update.");
        return nil;
    }
    
    GSSunlightNeighborhood *sunNeighborhood = [[GSSunlightNeighborhood alloc] init];
    
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSGridSlot *slot = [sunSlots neighborAtIndex:i];
        GSChunkSunlightData *neighbor = (GSChunkSunlightData *)slot.item;
        [sunNeighborhood setNeighborAtIndex:i neighbor:neighbor];
    }

    GSVoxelNeighborhood *originalVoxelNeighborhood = sunlight.neighborhood;
    assert(originalVoxelNeighborhood);
    GSVoxelNeighborhood *voxelNeighborhood = [originalVoxelNeighborhood copyReplacing:voxels1 withNeighbor:voxels2];
    sunNeighborhood.voxelNeighborhood = voxelNeighborhood;
    
    vector_long3 editPosClp = GSCastToIntegerVector3(_pos - voxels1.minP);
    GSVoxel originalVoxel = [voxels1 voxelAtLocalPosition:editPosClp];
    GSVoxel modifiedVoxel = [voxels2 voxelAtLocalPosition:editPosClp];
    BOOL removingLight = !originalVoxel.opaque && modifiedVoxel.opaque;

    nSunlight = [sunNeighborhood newSunlightBufferWithEditAtPoint:_pos
                                                    removingLight:removingLight
                                                 affectedAreaMinP:affectedAreaMinP
                                                 affectedAreaMaxP:affectedAreaMaxP];

    GSStopwatchTraceStep(@"Updated sunlight for the neighborhood.");
    return nSunlight;
}

- (void)invalidateChunksWithSlotsArray:(NSArray *)slotsArray
{
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        for(GSNeighborhood<GSGridSlot *> *slots in slotsArray)
        {
            GSGridSlot *slot = [slots neighborAtIndex:i];
            [slot.item invalidate];
            slot.item = nil;
        }
    }
}

- (void)updateNeighbor:(GSVoxelNeighborIndex)i
        originalVoxels:(nonnull GSChunkVoxelData *)voxels1
     replacementVoxels:(nonnull GSChunkVoxelData *)voxels2
  neighborhoodSunlight:(nonnull GSTerrainBuffer *)nSunlight
      affectedAreaMinP:(vector_long3)affectedAreaMinP
      affectedAreaMaxP:(vector_long3)affectedAreaMaxP
              sunSlots:(nonnull GSNeighborhood<GSGridSlot *> *)sunSlots
              geoSlots:(nonnull GSNeighborhood<GSGridSlot *> *)geoSlots
              vaoSlots:(nonnull GSNeighborhood<GSGridSlot *> *)vaoSlots
{
    NSParameterAssert(voxels1);
    NSParameterAssert(voxels2);
    NSParameterAssert(nSunlight);
    NSParameterAssert(sunSlots);
    NSParameterAssert(geoSlots);
    NSParameterAssert(vaoSlots);
    NSParameterAssert((affectedAreaMaxP.x > affectedAreaMinP.x) &&
                      (affectedAreaMaxP.y > affectedAreaMinP.y) &&
                      (affectedAreaMaxP.z > affectedAreaMinP.z));

    GSChunkSunlightData *sunlight2 = nil;
    GSChunkGeometryData *geo2 = nil;
    
    // If the affected area does not include this neighbor then skip it.
    {
        vector_float3 foffset = [GSNeighborhood offsetForNeighborIndex:i];
        
        struct { vector_long3 mins, maxs; } a, b;
        
        a.mins = GSCastToIntegerVector3(foffset);
        a.maxs = a.mins + GSChunkSizeIntVec3;
        
        b.mins = affectedAreaMinP;
        b.maxs = affectedAreaMaxP;

        BOOL intersects = (a.mins.x <= b.maxs.x) && (a.maxs.x >= b.mins.x) &&
                          (a.mins.y <= b.maxs.y) && (a.maxs.y >= b.mins.y) &&
                          (a.mins.z <= b.maxs.z) && (a.maxs.z >= b.mins.z);
        
        if (!intersects) {
            return;
        }
    }
    
    // Update sunlight.
    {
        GSGridSlot *sunSlot = [sunSlots neighborAtIndex:i];
        GSChunkSunlightData *sunlight1 = (GSChunkSunlightData *)sunSlot.item;
        
        if (sunlight1) {
            [sunlight1 invalidate];
            
            vector_float3 slotMinP = sunSlot.minP - GSMinCornerForChunkAtPoint(_pos);
            vector_long3 minP = GSCastToIntegerVector3(slotMinP);
            GSVoxelNeighborhood *neighborhood = [sunlight1.neighborhood copyReplacing:voxels1 withNeighbor:voxels2];
            vector_long3 a = minP + GSMakeIntegerVector3(-1, 0, -1);
            vector_long3 b = minP + GSMakeIntegerVector3(1, 0, 1) + GSChunkSizeIntVec3;
            GSTerrainBuffer *sunlight = [nSunlight copySubBufferWithMinCorner:a maxCorner:b];
            sunlight2 = [sunlight1 copyReplacingSunlightData:sunlight neighborhood:neighborhood];
        }
        
        sunSlot.item = sunlight2;
        GSStopwatchTraceStep(@"Updated sunlight at %@", [GSBoxedVector boxedVectorWithVector:sunSlot.minP]);
    }
    
    // Update geometry.
    {
        GSGridSlot *geoSlot = [geoSlots neighborAtIndex:i];
        GSChunkGeometryData *geo1 = (GSChunkGeometryData *)geoSlot.item;
        
        if (geo1) {
            [geo1 invalidate];
            
            /* XXX: Potential performance improvement here. The copyWithEdit method can be made faster by only
             * re-propagating sunlight in the region affected by the edit; not across the entire chunk.
             */
            if(sunlight2) {
                geo2 = [geo1 copyWithSunlight:sunlight2];
            }
        }
        
        geoSlot.item = geo2;
        GSStopwatchTraceStep(@"Updated geometry at %@", [GSBoxedVector boxedVectorWithVector:geoSlot.minP]);
    }
    
    // Update the Vertex Array Object.
    {
        GSChunkVAO *vao2 = nil;
        GSGridSlot *vaoSlot = [vaoSlots neighborAtIndex:i];
        GSChunkVAO *vao1 = (GSChunkVAO *)vaoSlot.item;
        
        if (vao1) {
            [vao1 invalidate];
            
            if (geo2) {
                vao2 = [[GSChunkVAO alloc] initWithChunkGeometry:geo2 glContext:vao1.glContext];
            }
        }
        
        vaoSlot.item = vao2;
        GSStopwatchTraceStep(@"Updated VAO at %@", [GSBoxedVector boxedVectorWithVector:vaoSlot.minP]);
    }
}

- (void)main
{
    GSBoxedVector *boxedPos = [GSBoxedVector boxedVectorWithVector:_pos];
    
    if (_journal) {
        GSStopwatchTraceBegin(@"placeBlockAtPoint enter %@", boxedPos);

        GSTerrainJournalEntry *entry = [[GSTerrainJournalEntry alloc] init];
        entry.value = _block;
        entry.position = boxedPos;
        [_journal addEntry:entry];
    }
    
    GSNeighborhood<GSGridSlot *> *voxSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *sunSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *geoSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *vaoSlots = [[GSNeighborhood alloc] init];
    NSArray *gridSlots = @[vaoSlots, geoSlots, sunSlots, voxSlots];
    
    // Get slots.
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
        vector_float3 neighborPos = offset + GSMinCornerForChunkAtPoint(_pos);
        
        [voxSlots setNeighborAtIndex:i neighbor:[_chunkStore.gridVoxelData slotAtPoint:neighborPos]];
        [sunSlots setNeighborAtIndex:i neighbor:[_chunkStore.gridSunlightData slotAtPoint:neighborPos]];
        [geoSlots setNeighborAtIndex:i neighbor:[_chunkStore.gridGeometryData slotAtPoint:neighborPos]];
        [vaoSlots setNeighborAtIndex:i neighbor:[_chunkStore.gridVAO slotAtPoint:neighborPos]];
    }
    
    // Acquire slot locks upfront.
    for(GSNeighborhood<GSGridSlot *> *slots in gridSlots)
    {
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            GSGridSlot *slot = [slots neighborAtIndex:i];
            [slot.lock lockForWriting];
        }
    }
    GSStopwatchTraceStep(@"Acquired slot locks.");

    // Update the voxels for the neighborhood.
    GSChunkVoxelData *voxels1 = nil;
    GSChunkVoxelData *voxels2 = nil;
    [self updateVoxelsWithVoxelSlots:voxSlots originalVoxels:&voxels1 replacementVoxels:&voxels2];

    // Update sunlight for the neighborhood.
    vector_long3 affectedAreaMinP, affectedAreaMaxP;
    GSTerrainBuffer *nSunlight = [self updateSunlightWithSunSlots:sunSlots
                                                   originalVoxels:voxels1
                                                replacementVoxels:voxels2
                                                 affectedAreaMinP:&affectedAreaMinP
                                                 affectedAreaMaxP:&affectedAreaMaxP];

    if (!nSunlight) {
        // We don't have sunlight, so we simply invalidate all the items held by these slots.
        [self invalidateChunksWithSlotsArray:@[sunSlots, geoSlots, vaoSlots]];
    } else {
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            [self updateNeighbor:i
                  originalVoxels:voxels1
               replacementVoxels:voxels2
            neighborhoodSunlight:nSunlight
                affectedAreaMinP:affectedAreaMinP
                affectedAreaMaxP:affectedAreaMaxP
                        sunSlots:sunSlots
                        geoSlots:geoSlots
                        vaoSlots:vaoSlots];
        }
    }

    // Release locks.
    for(GSNeighborhood<GSGridSlot *> *slots in [gridSlots reverseObjectEnumerator])
    {
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            GSGridSlot *slot = [slots neighborAtIndex:i];
            [slot.lock unlockForWriting];
        }
    }
    GSStopwatchTraceStep(@"Released slot locks.");
    
    if (_journal) {
        GSStopwatchTraceEnd(@"placeBlockAtPoint exit %@", boxedPos);
    }
}

@end
