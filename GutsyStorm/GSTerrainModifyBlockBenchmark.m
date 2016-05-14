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
    vector_float3 positions[] = {
        vector_make(53.0, 54.0, 81.0),
        vector_make(85.0, 12.0, 137.0)
    };
    for(size_t i=0, n=(sizeof(positions)/sizeof(*positions)); i<n; ++i)
    {
        vector_float3 p = positions[i];

        for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
        {
            vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            while(![_chunkStore nonBlockingVaoAtPoint:[GSBoxedVector boxedVectorWithVector:p+offset] createIfMissing:YES]);
            [_chunkStore chunkVoxelsAtPoint:p];
        }
    }
}

- (void)tearDown
{
    [_terrain shutdown];
    _chunkStore = nil;
    _terrain = nil;
}

- (void)benchmarkDigThroughFloatingIsland
{
    vector_float3 p = vector_make(53.0, 54.0, 81.0);

    uint64_t averageTime = dispatch_benchmark(3, ^{
        
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

- (void)benchmarkDigInTheOpen
{
    uint64_t averageTime = dispatch_benchmark(11, ^{
        const size_t n = 5;
        vector_float3 positions[n] = {
            vector_make(85.0, 13.0, 138.0),
            vector_make(85.0, 13.0, 137.0),
            vector_make(85.0, 12.0, 137.0),
            vector_make(85.0, 12.0, 136.0),
            vector_make(85.0, 11.0, 136.0)
        };

        for(int i = 0; i < n; ++i)
        {
            GSTerrainModifyBlockOperation *op;
            op = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                     block:empty
                                                                 operation:Set
                                                                  position:positions[i]
                                                                   journal:nil];
            [op main];
        }

        for(int i = n-1; i >= 0; --i)
        {
            GSTerrainModifyBlockOperation *op;
            op = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                     block:cube
                                                                 operation:Set
                                                                  position:positions[i]
                                                                   journal:nil];
            [op main];
        }
    });
    
    NSLog(@"%s: %llu ms", __PRETTY_FUNCTION__, averageTime / NSEC_PER_MSEC);
}

- (void)run
{
    [self setUp];
    [self benchmarkDigThroughFloatingIsland];
    [self tearDown];
    
    [self setUp];
    [self benchmarkDigInTheOpen];
    [self tearDown];
}

@end
