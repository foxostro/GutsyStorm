//
//  GSTerrainModifyBlockBenchmark.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/13/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainModifyBlockBenchmark.h"

#import "GSTerrain.h"
#import "GSTerrainJournal.h"
#import "GSTerrainChunkStore.h"
#import "GSCamera.h"
#import "GSBoxedVector.h"
#import "GSNeighborhood.h"
#import "GSActivity.h"
#import "GSVectorUtils.h"
#import "GSTerrainModifyBlockOperation.h"


extern uint64_t dispatch_benchmark(size_t count, void (^block)(void));


@implementation GSTerrainModifyBlockBenchmark
{
    NSOpenGLContext *_context;
    GSTerrainJournal *_journal;
    GSTerrain *_terrain;
    GSTerrainChunkStore *_chunkStore;
    GSVoxel cube, empty;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithOpenGLContext:(nonnull NSOpenGLContext *)context
{
    NSParameterAssert(context);
    if (self = [super init]) {
        _context = context;
    }
    return self;
}

- (void)setUp
{
    GSCamera *camera = [[GSCamera alloc] init];
 
    _journal = [[GSTerrainJournal alloc] init];
    _terrain = [[GSTerrain alloc] initWithJournal:_journal cacheFolder:nil camera:camera glContext:_context];
    _chunkStore = _terrain.chunkStore;
    _chunkStore.enableLoadingFromCacheFolder = NO;
    
    bzero(&cube, sizeof(GSVoxel));
    cube.opaque = YES;
    cube.dir = VOXEL_DIR_NORTH;
    cube.type = VOXEL_TYPE_CUBE;
    
    bzero(&empty, sizeof(GSVoxel));
    empty.opaque = NO;
    empty.dir = VOXEL_DIR_NORTH;
    empty.type = VOXEL_TYPE_EMPTY;
    
    // Make sure chunk gets loaded before we enter start the benchmark.
    vector_float3 p = vector_make(53.0, 54.0, 81.0);
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
        while(![_chunkStore nonBlockingVaoAtPoint:[GSBoxedVector boxedVectorWithVector:p+offset] createIfMissing:YES]);
        [_chunkStore chunkVoxelsAtPoint:p];
    }
}

- (void)tearDown
{
    [_terrain shutdown];
    _chunkStore = nil;
    _terrain = nil;
}

- (void)benchmarkPlaceAndRemove
{
    vector_float3 p = vector_make(53.0, 54.0, 81.0);

    uint64_t averageTime = dispatch_benchmark(11, ^{
        
        for(p.y = 54; p.y >= 26; --p.y)
        {
            GSTerrainModifyBlockOperation *op;
            op = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                     block:empty
                                                                 operation:Set
                                                                  position:p
                                                                   journal:nil];
            [op main];
        }
    });

    NSLog(@"%s: %llu ms", __PRETTY_FUNCTION__, averageTime / NSEC_PER_MSEC);
}

- (void)run
{
    [self setUp];
    [self benchmarkPlaceAndRemove];
    [self tearDown];
}

@end
