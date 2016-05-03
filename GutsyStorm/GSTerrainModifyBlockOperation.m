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
#import "GSNeighborhood.h"


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

- (nonnull NSSet<GSBoxedVector *> *)sunlightChunksInvalidatedByChangeAtPoint:(vector_float3)p
                                                              originalVoxels:(nonnull GSChunkVoxelData *)voxels1
                                                              modifiedVoxels:(nullable GSChunkVoxelData *)voxels2
{
    // The caller must ensure that the grids stay consistent with one another during the call to this method.
    
    NSParameterAssert(voxels1);
    
    if (!voxels2) {
        GSTerrainBufferElement m = CHUNK_LIGHTING_MAX;
        NSArray *points = @[[GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p)],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(+m,  0,  0))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(-m,  0,  0))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, +m))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, -m))],
                            ];
        NSSet *set = [NSSet setWithArray:points];
        return set;
    }
    
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    vector_long3 clpOfEdit = GSMakeIntegerVector3(p.x - minP.x, p.y - minP.y, p.z - minP.z);
    
    // If the change is deep enough into the interior of the block then the change cannot affect the neighbors.
    if (clpOfEdit.x >= CHUNK_LIGHTING_MAX && clpOfEdit.z >= CHUNK_LIGHTING_MAX &&
        clpOfEdit.x < (CHUNK_SIZE_X-CHUNK_LIGHTING_MAX) && clpOfEdit.z < (CHUNK_SIZE_Z-CHUNK_LIGHTING_MAX)) {
        return [NSSet setWithObject:[GSBoxedVector boxedVectorWithVector:minP]];
    }
    
    GSVoxel originalVoxel = [voxels1 voxelAtLocalPosition:clpOfEdit];
    GSVoxel modifiedVoxel = [voxels2 voxelAtLocalPosition:clpOfEdit];
    
    BOOL originalIsOpaque = originalVoxel.opaque;
    BOOL modifiedIsOpaque = modifiedVoxel.opaque;
    
    // If the original block was opaque, and the new block is opaque, then the change actually can be resolved by
    // updating sunlight for the one block that was modified, and nothing else.
    // If the original block was not-opaque and the new block is also not-opaque then the change can be resolved as in
    // the above case. Only one sunlight block needs to be updated.
    if (originalIsOpaque == modifiedIsOpaque) {
        return [NSSet setWithObject:[GSBoxedVector boxedVectorWithVector:minP]];
    }
    
    GSTerrainBufferElement m = CHUNK_LIGHTING_MAX;
    
    // If the original block was opaque, and the new block is not-opaque, then the change cannot propagate a further
    // distance than the difference between the the maximum and minimum adjacent light levels. Noting, however, that
    // light levels of opaque blocks must be ignored.
    //
    // If the original block was not-opaque and the new block is opaque then the change probably needs be resolved
    // by actually computing the sunlight propagation first. We have a few options here: We could assume the
    // propagation will continue for the maximum distance. We could perform a flood-fill throughout the chunk to
    // determine whether it would touch the neighboring chunks. Or, we could optimize for the special case where we
    // place an opaque block on top of an opaque block. In this particular case, which we expect to be common,
    // the max-min difference technique will work correctly.
    BOOL removingBlock = originalIsOpaque && !modifiedIsOpaque;
    
    BOOL bottomBlockIsOpaque;
    if (clpOfEdit.y >= 1) {
        GSVoxel bottomVoxel = [voxels2 voxelAtLocalPosition:(clpOfEdit + GSMakeIntegerVector3(0, -1, 0))];
        bottomBlockIsOpaque = bottomVoxel.opaque;
    } else {
        bottomBlockIsOpaque = NO;
    }
    
    if (removingBlock || bottomBlockIsOpaque) {
        GSTerrainBufferElement maxSunlight = 0, minSunlight = CHUNK_LIGHTING_MAX;
        
        // Is the edit on the border of the chunk? If so then testing the adjacent chunks would involve taking a lock on
        // the neighboring chunks. If that's the case then skip neighbor tests and assume the edit affects the full
        // range. We do this because, upon entering this method, we're already holding a lock on the stripe which
        // contains the chunk which contains the edit. If we attempt to take the lock on another voxel data chunk, and
        // both chunks reside on the same stripe, then taking the lock will cause a deadlock.
        if (clpOfEdit.x > 0 && clpOfEdit.z > 0 && clpOfEdit.x < (CHUNK_SIZE_X-1) && clpOfEdit.z < (CHUNK_SIZE_Z-1)) {
            vector_long3 adjacentPoints[] = {
                clpOfEdit,
                clpOfEdit + GSMakeIntegerVector3(+1,  0,  0),
                clpOfEdit + GSMakeIntegerVector3(-1,  0,  0),
                clpOfEdit + GSMakeIntegerVector3( 0, +1,  0),
                clpOfEdit + GSMakeIntegerVector3( 0, -1,  0),
                clpOfEdit + GSMakeIntegerVector3( 0,  0, +1),
                clpOfEdit + GSMakeIntegerVector3( 0,  0, -1)
            };
            
            GSGridSlot *slot = [_chunkStore.gridSunlightData slotAtPoint:p];
            GSChunkSunlightData *sunChunk = (GSChunkSunlightData *)slot.item;
            
            if (sunChunk) for(size_t i = 0; i < ARRAY_LEN(adjacentPoints); ++i)
            {
                vector_long3 adjacentPoint = adjacentPoints[i];
                
                if (adjacentPoint.y >= 0 && adjacentPoint.y < CHUNK_SIZE_Y) {
                    GSVoxel voxel = [voxels1 voxelAtLocalPosition:adjacentPoint];
                    
                    if (!voxel.opaque) {
                        GSTerrainBufferElement sunlightLevel = [sunChunk.sunlight valueAtPosition:adjacentPoint];
                        maxSunlight = MAX(maxSunlight, sunlightLevel);
                        minSunlight = MIN(minSunlight, sunlightLevel);
                    }
                }
            }
            
            m = maxSunlight - minSunlight;
        }
    }
    
    NSArray *points = @[[GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p)],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(+m,  0,  0))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(-m,  0,  0))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, +m))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, -m))],
                        ];
    NSSet *set = [NSSet setWithArray:points];
    return set;
}

- (void)run
{
    GSBoxedVector *boxedPos = [GSBoxedVector boxedVectorWithVector:_pos];
    
    if (_journal) {
        // XXX: saving the journal should be done asynchronously on a separate thread
        GSTerrainJournalEntry *entry = [[GSTerrainJournalEntry alloc] init];
        entry.value = _block;
        entry.position = boxedPos;
        [_journal addEntry:entry];
        GSStopwatchTraceBegin(@"placeBlockAtPoint enter %@", boxedPos);
    }
    
    NSMutableDictionary<GSBoxedVector *, GSGridSlot *> *sunSlots = [NSMutableDictionary new];
    NSMutableDictionary<GSBoxedVector *, GSGridSlot *> *geoSlots = [NSMutableDictionary new];
    NSMutableDictionary<GSBoxedVector *, GSGridSlot *> *vaoSlots = [NSMutableDictionary new];
    NSArray *gridSlots = @[vaoSlots, geoSlots, sunSlots];
    GSGridSlot *voxSlot;
    
    // Acquire slots.
    voxSlot = [_chunkStore.gridVoxelData slotAtPoint:_pos];
    {
        GSTerrainBufferElement m = CHUNK_LIGHTING_MAX;
        NSArray *points = @[[GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(_pos)],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(_pos + vector_make(+m,  0,  0))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(_pos + vector_make(-m,  0,  0))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(_pos + vector_make( 0,  0, +m))],
                            [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(_pos + vector_make( 0,  0, -m))],
                            ];
        NSSet *set = [NSSet setWithArray:points];
        for(GSBoxedVector *boxedPoint in set)
        {
            sunSlots[boxedPoint] = [_chunkStore.gridSunlightData slotAtPoint:[boxedPoint vectorValue]];
            geoSlots[boxedPoint] = [_chunkStore.gridGeometryData slotAtPoint:[boxedPoint vectorValue]];
            vaoSlots[boxedPoint] = [_chunkStore.gridVAO slotAtPoint:[boxedPoint vectorValue]];
        }
    }
    
    // Acquire locks upfront.
    for(NSMutableDictionary *slots in gridSlots)
    {
        for(GSGridSlot *slot in [slots objectEnumerator])
        {
            [slot.lock lockForWriting];
        }
    }
    [voxSlot.lock lockForWriting];
    
    GSChunkVoxelData *voxels1 = nil;
    GSChunkVoxelData *voxels2 = nil;
    
    voxels1 = (GSChunkVoxelData *)voxSlot.item;
    if (!voxels1) {
        voxels1 = [_chunkStore newVoxelChunkAtPoint:_pos];
    } else {
        [voxels1 invalidate];
        voxels2 = [voxels1 copyWithEditAtPoint:_pos block:_block];
        [voxels2 saveToFile];
        voxSlot.item = voxels2;
    }
    
    GSStopwatchTraceStep(@"Updated voxels.");
    
    /* XXX: Consider replacing sunlightChunksInvalidatedByVoxelChangeAtPoint with a flood-fill constrained to the
     * local neighborhood. If the flood-fill would exit the center chunk then take note of which chunk because that
     * one needs invalidation too.
     */
    NSSet<GSBoxedVector *> *points = [self sunlightChunksInvalidatedByChangeAtPoint:_pos
                                                                     originalVoxels:voxels1
                                                                     modifiedVoxels:voxels2];
    GSStopwatchTraceStep(@"Estimated affected sunlight chunks: %@", points);
    
    for(GSBoxedVector *bp in points)
    {
        GSChunkSunlightData *sunlight2 = nil;
        GSChunkGeometryData *geo2 = nil;
        
        // Update sunlight.
        {
            GSGridSlot *sunSlot = sunSlots[bp];
            GSChunkSunlightData *sunlight1 = (GSChunkSunlightData *)sunSlot.item;
            
            if (sunlight1) {
                [sunlight1 invalidate];
                
                GSNeighborhood *neighborhood = [sunlight1.neighborhood copyReplacing:voxels1 withNeighbor:voxels2];
                
                /* XXX: Potential performance improvement here. The copyWithEdit method can be made faster by only
                 * re-propagating sunlight in the region affected by the edit; not across the entire chunk.
                 */
                sunlight2 = [sunlight1 copyWithEditAtPoint:_pos neighborhood:neighborhood];
            }
            
            sunSlot.item = sunlight2;
        }
        GSStopwatchTraceStep(@"Updated sunlight at %@", bp);
        
        // Update geometry.
        {
            GSGridSlot *geoSlot = geoSlots[bp];
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
        }
        GSStopwatchTraceStep(@"Updated geometry at %@", bp);
        
        // Update the Vertex Array Object.
        {
            GSChunkVAO *vao2 = nil;
            GSGridSlot *vaoSlot = vaoSlots[bp];
            GSChunkVAO *vao1 = (GSChunkVAO *)vaoSlot.item;

            if (vao1) {
                [vao1 invalidate];

                if (geo2) {
                    vao2 = [[GSChunkVAO alloc] initWithChunkGeometry:geo2 glContext:vao1.glContext];
                }
            }

            vaoSlot.item = vao2;
        }
        GSStopwatchTraceStep(@"Updated VAO at %@", bp);
    }
    
    // Release locks.
    [voxSlot.lock unlockForWriting];
    for(NSMutableDictionary *slots in [gridSlots reverseObjectEnumerator])
    {
        for(GSGridSlot *slot in [slots objectEnumerator])
        {
            [slot.lock unlockForWriting];
        }
    }
    
    if (_journal) {
        GSStopwatchTraceEnd(@"placeBlockAtPoint exit %@", boxedPos);
    }
}

@end
