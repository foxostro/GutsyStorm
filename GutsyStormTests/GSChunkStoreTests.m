//
//  GSChunkStoreTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/30/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSTerrain.h"
#import "GSTerrainJournal.h"
#import "GSChunkStore.h"
#import "GSCamera.h"
#import "GSBoxedVector.h"
#import "GSNeighborhood.h"

@interface GSChunkStoreTests : XCTestCase

@end

@implementation GSChunkStoreTests
{
    GSTerrain *_terrain;
    GSChunkStore *_chunkStore;
    GSVoxel cube, empty;
}

- (void)setUp
{
    [super setUp];
    GSTerrainJournal *journal = [[GSTerrainJournal alloc] init];
    GSCamera *camera = [[GSCamera alloc] init];
    NSOpenGLPixelFormatAttribute glAttributes[] = {0};
    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:glAttributes];
    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    
    _terrain = [[GSTerrain alloc] initWithJournal:journal camera:camera glContext:context];
    _chunkStore = _terrain.chunkStore;
    
    bzero(&cube, sizeof(GSVoxel));
    cube.opaque = YES;
    cube.dir = VOXEL_DIR_NORTH;
    cube.type = VOXEL_TYPE_CUBE;
    
    bzero(&empty, sizeof(GSVoxel));
    empty.opaque = NO;
    empty.dir = VOXEL_DIR_NORTH;
    empty.type = VOXEL_TYPE_EMPTY;
    
    // Make sure chunk gets loaded before we enter -measureBlock:.
    vector_float3 p = vector_make(90.0, 4.0, 127.0);
    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
        while(![_chunkStore nonBlockingVaoAtPoint:[GSBoxedVector boxedVectorWithVector:p+offset] createIfMissing:YES]);
        [_chunkStore voxelAtPoint:p];
    }
}

- (void)tearDown
{
    [_terrain shutdown];
    _chunkStore = nil;
    _terrain = nil;

    [super tearDown];
}

- (void)testPlaceAndRemoveBlock
{
    vector_float3 p = vector_make(90.0, 4.0, 127.0);
    [self measureBlock:^{
        [_chunkStore placeBlockAtPoint:p block:empty addToJournal:NO];
        [_chunkStore placeBlockAtPoint:p block:cube addToJournal:NO];
    }];
}

@end
