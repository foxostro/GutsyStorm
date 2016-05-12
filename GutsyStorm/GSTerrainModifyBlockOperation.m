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
#import "GSAABB.h"


#define ARRAY_LEN(a) (sizeof(a)/sizeof(a[0]))


static void logEditInJournal(GSTerrainJournal * _Nullable journal,
                             GSVoxel blockToPlace,
                             vector_float3 editPos)
{
    if (journal) {
        GSBoxedVector *boxedPos = [GSBoxedVector boxedVectorWithVector:editPos];
        
        GSStopwatchTraceBegin(@"placeBlockAtPoint enter %@", boxedPos);
        
        GSTerrainJournalEntry *entry = [[GSTerrainJournalEntry alloc] init];
        entry.value = blockToPlace;
        entry.position = boxedPos;
        [journal addEntry:entry];
    }
}

static void fetchSlots(GSTerrainChunkStore * _Nonnull chunkStore,
                       vector_float3 editPos,
                       GSNeighborhood<GSGridSlot *> * _Nonnull voxSlots,
                       GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                       GSNeighborhood<GSGridSlot *> * _Nonnull geoSlots,
                       GSNeighborhood<GSGridSlot *> * _Nonnull vaoSlots)
{
    assert(chunkStore);
    assert(voxSlots);
    assert(sunSlots);
    assert(geoSlots);
    assert(vaoSlots);

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
        vector_float3 neighborPos = offset + GSMinCornerForChunkAtPoint(editPos);
        
        [voxSlots setNeighborAtIndex:i neighbor:[chunkStore.gridVoxelData slotAtPoint:neighborPos]];
        [sunSlots setNeighborAtIndex:i neighbor:[chunkStore.gridSunlightData slotAtPoint:neighborPos]];
        [geoSlots setNeighborAtIndex:i neighbor:[chunkStore.gridGeometryData slotAtPoint:neighborPos]];
        [vaoSlots setNeighborAtIndex:i neighbor:[chunkStore.gridVAO slotAtPoint:neighborPos]];
    }
}

static void acquireLocks(GSNeighborhood<GSGridSlot *> * _Nonnull voxSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull geoSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull vaoSlots)
{
    assert(voxSlots);
    assert(sunSlots);
    assert(geoSlots);
    assert(vaoSlots);

    for(GSNeighborhood<GSGridSlot *> *slots in @[vaoSlots, geoSlots, sunSlots, voxSlots])
    {
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            GSGridSlot *slot = [slots neighborAtIndex:i];
            [slot.lock lockForWriting];
        }
    }
    GSStopwatchTraceStep(@"Acquired slot locks.");
}

static void releaseLocks(GSNeighborhood<GSGridSlot *> * _Nonnull voxSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull geoSlots,
                         GSNeighborhood<GSGridSlot *> * _Nonnull vaoSlots)
{
    assert(voxSlots);
    assert(sunSlots);
    assert(geoSlots);
    assert(vaoSlots);
    
    for(GSNeighborhood<GSGridSlot *> *slots in @[voxSlots, sunSlots, geoSlots, vaoSlots])
    {
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            GSGridSlot *slot = [slots neighborAtIndex:i];
            [slot.lock unlockForWriting];
        }
    }
    GSStopwatchTraceStep(@"Released slot locks.");
}

static void updateVoxels(GSTerrainChunkStore * _Nonnull chunkStore,
                         GSVoxel blockToPlace, GSVoxelBitwiseOp op,
                         vector_float3 editPos,
                         GSNeighborhood<GSGridSlot *> * _Nonnull voxSlots,
                         GSChunkVoxelData * _Nonnull * _Nonnull outVoxels1,
                         GSChunkVoxelData * _Nonnull * _Nonnull outVoxels2)
{
    assert(chunkStore);
    assert(voxSlots);
    assert(outVoxels1);
    assert(outVoxels2);

    GSChunkVoxelData *voxels1, *voxels2;

    GSGridSlot *voxSlot = [voxSlots neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    voxels1 = (GSChunkVoxelData *)voxSlot.item;
    if (!voxels1) {
        voxels1 = [chunkStore newVoxelChunkAtPoint:editPos];
    }
    [voxels1 invalidate];
    voxels2 = [voxels1 copyWithEditAtPoint:editPos block:blockToPlace operation:op];
    [voxels2 saveToFile];
    voxSlot.item = voxels2;

    *outVoxels1 = voxels1;
    *outVoxels2 = voxels2;

    GSStopwatchTraceStep(@"Updated voxels.");
}

static void calculateNeighborhoodSunlight(vector_float3 editPos,
                                          GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                                          GSChunkVoxelData * _Nonnull voxels1,
                                          GSChunkVoxelData * _Nonnull voxels2,
                                          GSIntAABB * _Nullable affectedRegion,
                                          GSTerrainBuffer **outNeighborhoodSunlight)
{
    assert(outNeighborhoodSunlight);
    assert(voxels1);
    assert(voxels2);

    GSTerrainBuffer *nSunlight = nil;
    
    GSGridSlot *sunSlot = [sunSlots neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    GSChunkSunlightData *sunlight = (GSChunkSunlightData *)sunSlot.item;
    
    if (!sunlight) {
        GSStopwatchTraceStep(@"Skipping sunlight update.");
        *outNeighborhoodSunlight = nil;
        return;
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
    
    vector_long3 editPosClp = GSCastToIntegerVector3(editPos - voxels1.minP);
    GSVoxel originalVoxel = [voxels1 voxelAtLocalPosition:editPosClp];
    GSVoxel modifiedVoxel = [voxels2 voxelAtLocalPosition:editPosClp];
    BOOL removingLight = (!originalVoxel.opaque && modifiedVoxel.opaque) ||
                         (originalVoxel.torch && !modifiedVoxel.torch);

    nSunlight = [sunNeighborhood newSunlightBufferWithEditAtPoint:editPos
                                                    removingLight:removingLight
                                                   affectedRegion:affectedRegion];
    
    GSStopwatchTraceStep(@"Updated sunlight for the neighborhood.");
    *outNeighborhoodSunlight = nSunlight;
}

static void invalidateDependentChunks(GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                                      GSNeighborhood<GSGridSlot *> * _Nonnull geoSlots,
                                      GSNeighborhood<GSGridSlot *> * _Nonnull vaoSlots)
{
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GSGridSlot *slot;
        
        slot = [sunSlots neighborAtIndex:i];
        [slot.item invalidate];
        slot.item = nil;
        
        slot = [geoSlots neighborAtIndex:i];
        [slot.item invalidate];
        slot.item = nil;
        
        slot = [vaoSlots neighborAtIndex:i];
        [slot.item invalidate];
        slot.item = nil;
    }
}

static void rebuildDependentChunks(GSVoxelNeighborIndex i,
                                   vector_float3 editPos,
                                   GSChunkVoxelData * _Nonnull voxels1,
                                   GSChunkVoxelData * _Nonnull voxels2,
                                   GSTerrainBuffer * _Nonnull nSunlight,
                                   GSIntAABB * _Nonnull affectedRegion,
                                   GSNeighborhood<GSGridSlot *> * _Nonnull sunSlots,
                                   GSNeighborhood<GSGridSlot *> * _Nonnull geoSlots,
                                   GSNeighborhood<GSGridSlot *> * _Nonnull vaoSlots)
{
    assert(voxels1);
    assert(voxels2);
    assert(nSunlight);
    assert(affectedRegion);
    assert(sunSlots);
    assert(geoSlots);
    assert(vaoSlots);
    assert((affectedRegion->maxs.x > affectedRegion->mins.x) &&
           (affectedRegion->maxs.y > affectedRegion->mins.y) &&
           (affectedRegion->maxs.z > affectedRegion->mins.z));
    
    GSChunkSunlightData *sunlight2 = nil;
    GSChunkGeometryData *geo2 = nil;
    
    // If the affected area does not include this neighbor then skip it.
    {
        GSIntAABB a;
        a.mins = GSCastToIntegerVector3([GSNeighborhood offsetForNeighborIndex:i]);
        a.maxs = a.mins + GSChunkSizeIntVec3;

        if (!GSIntAABBIntersects(&a, affectedRegion)) {
            return;
        }
    }
    
    // Update sunlight.
    {
        GSGridSlot *sunSlot = [sunSlots neighborAtIndex:i];
        GSChunkSunlightData *sunlight1 = (GSChunkSunlightData *)sunSlot.item;
        
        if (sunlight1) {
            [sunlight1 invalidate];
            
            vector_float3 slotMinP = sunSlot.minP - GSMinCornerForChunkAtPoint(editPos);
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

            if(sunlight2) {
                geo2 = [geo1 copyWithSunlight:sunlight2 invalidatedRegion:affectedRegion];
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


@implementation GSTerrainModifyBlockOperation
{
    GSTerrainChunkStore *_chunkStore;
    GSVoxel _block;
    GSVoxelBitwiseOp _op;
    vector_float3 _pos;
    GSTerrainJournal *_journal;
}

- (nonnull instancetype)init NS_UNAVAILABLE
{
    @throw nil;
}

- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
                                     block:(GSVoxel)block
                                 operation:(GSVoxelBitwiseOp)op
                                  position:(vector_float3)pos
                                   journal:(nullable GSTerrainJournal *)journal
{
    if (self = [super init]) {
        _chunkStore = chunkStore;
        _block = block;
        _pos = pos;
        _op = op;
        _journal = journal;
    }
    return self;
}

- (void)main
{
    logEditInJournal(_journal, _block, _pos);

    GSNeighborhood<GSGridSlot *> *voxSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *sunSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *geoSlots = [[GSNeighborhood alloc] init];
    GSNeighborhood<GSGridSlot *> *vaoSlots = [[GSNeighborhood alloc] init];

    // Acquire slot locks upfront. We perform the modification while holding locks on the whole neighborhood.
    fetchSlots(_chunkStore, _pos, voxSlots, sunSlots, geoSlots, vaoSlots);
    acquireLocks(voxSlots, sunSlots, geoSlots, vaoSlots);

    // Update the voxels for the neighborhood.
    GSChunkVoxelData *voxels1 = nil;
    GSChunkVoxelData *voxels2 = nil;
    updateVoxels(_chunkStore, _block, _op, _pos, voxSlots, &voxels1, &voxels2);

    // Update sunlight for the neighborhood.
    GSIntAABB affectedRegion;
    GSTerrainBuffer *nSunlight;
    calculateNeighborhoodSunlight(_pos, sunSlots, voxels1, voxels2, &affectedRegion, &nSunlight);

    if (!nSunlight) {
        // We don't have sunlight, so we simply invalidate all the items held by these slots.
        invalidateDependentChunks(sunSlots, geoSlots, vaoSlots);
    } else {
        // Rebuild the chain of dependent chunks using the updated voxels and sunlight.
        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            rebuildDependentChunks(i, _pos, voxels1, voxels2, nSunlight, &affectedRegion, sunSlots, geoSlots, vaoSlots);
        }
    }

    releaseLocks(voxSlots, sunSlots, geoSlots, vaoSlots);

    if (_journal) {
        GSStopwatchTraceEnd(@"placeBlockAtPoint exit %@", [GSBoxedVector boxedVectorWithVector:_pos]);
    }
}

@end
