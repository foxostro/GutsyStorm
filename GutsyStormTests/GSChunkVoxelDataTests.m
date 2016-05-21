//
//  GSChunkVoxelDataTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/29/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSTerrainJournal.h"
#import "GSTerrainGenerator.h"
#import "GSChunkVoxelData.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


static const GSVoxel empty = {
    .outside = 0,
    .exposedToAirOnTop = 0,
    .opaque = 0,
    .upsideDown = 0,
    .dir = VOXEL_DIR_NORTH,
    .type = VOXEL_TYPE_EMPTY,
    .tex = VOXEL_TEX_DIRT,
};

static const GSVoxel cube = {
    .outside = 0,
    .exposedToAirOnTop = 0,
    .opaque = 1,
    .upsideDown = 0,
    .dir = VOXEL_DIR_NORTH,
    .type = VOXEL_TYPE_GROUND,
    .tex = VOXEL_TEX_DIRT,
};

static const int level = 10;


@interface GSChunkVoxelDataTests_TerrainGenerator : GSTerrainGenerator
@end

@implementation GSChunkVoxelDataTests_TerrainGenerator

- (void)generateWithDestination:(nonnull GSVoxel *)voxels
                          count:(NSUInteger)count
                         region:(nonnull GSIntAABB *)box
                  offsetToWorld:(vector_float3)offsetToWorld
{
    vector_long3 clp;
    FOR_BOX(clp, *box)
    {
        voxels[INDEX_BOX(clp, *box)] = (clp.y > level) ? empty : cube;
    }
}

@end


@interface GSChunkVoxelDataTests : XCTestCase

@end

@implementation GSChunkVoxelDataTests
{
    dispatch_group_t groupForSaving;
    dispatch_queue_t queueForSaving;
    GSTerrainJournal *journal;
    GSChunkVoxelData *chunk;
}

- (void)setUp
{
    [super setUp];

    groupForSaving = dispatch_group_create();
    queueForSaving = dispatch_queue_create("com.foxostro.GutsyStorm.GSChunkVoxelDataTests.queueForSaving",
                                           DISPATCH_QUEUE_SERIAL);
    journal = [[GSTerrainJournal alloc] init];
    chunk = [[GSChunkVoxelData alloc] initWithMinP:vector_make(0, 0, 0)
                                            folder:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                                    groupForSaving:groupForSaving
                                    queueForSaving:queueForSaving
                                           journal:journal
                                         generator:[[GSChunkVoxelDataTests_TerrainGenerator alloc] initWithRandomSeed:0]
                                      allowLoading:NO];
}

- (void)testBasicVoxelAccess
{
    GSVoxel block;
    
    block = [chunk voxelAtLocalPosition:GSMakeIntegerVector3(1, 1, 1)];
    XCTAssertEqual(block.type, cube.type);
    
    block = [chunk voxelAtLocalPosition:GSMakeIntegerVector3(1, 11, 1)];
    XCTAssertEqual(block.type, empty.type);
}

- (void)testOutsidenessCalculation
{
    GSVoxel block;
    
    block = [chunk voxelAtLocalPosition:GSMakeIntegerVector3(1, level, 1)];
    XCTAssertEqual(block.exposedToAirOnTop, 1);
    XCTAssertEqual(block.outside, 1);
}

- (void)testCopyWithEditOutside
{
    GSChunkVoxelData *modifiedChunk = [chunk copyWithEditAtPoint:vector_make(2, 15, 2) block:cube operation:Set];
    
    vector_long3 p = GSZeroIntVec3;
    GSIntAABB chunkBox = { GSZeroIntVec3, GSChunkSizeIntVec3 };
    FOR_BOX(p, chunkBox)
    {
        if (p.x == 2 && p.y == 15 && p.z == 2) {
            XCTAssertNotEqual([chunk voxelAtLocalPosition:p].type, [modifiedChunk voxelAtLocalPosition:p].type);
        } else {
            XCTAssertEqual([chunk voxelAtLocalPosition:p].type, [modifiedChunk voxelAtLocalPosition:p].type);
        }
    }

    GSVoxel block;
    
    block = [modifiedChunk voxelAtLocalPosition:GSMakeIntegerVector3(2, 15, 2)];
    XCTAssertEqual(block.type, cube.type);
    XCTAssertEqual(block.outside, 1);
    
    block = [modifiedChunk voxelAtLocalPosition:GSMakeIntegerVector3(2, 14, 2)];
    XCTAssertEqual(block.outside, 0);
}

- (void)testCopyWithEditInside
{
    GSChunkVoxelData *modifiedChunk = [chunk copyWithEditAtPoint:vector_make(2, 1, 2) block:empty operation:Set];
    
    vector_long3 p = GSZeroIntVec3;
    GSIntAABB chunkBox = { GSZeroIntVec3, GSChunkSizeIntVec3 };
    FOR_BOX(p, chunkBox)
    {
        if (p.x == 2 && p.y == 1 && p.z == 2) {
            XCTAssertNotEqual([chunk voxelAtLocalPosition:p].type, [modifiedChunk voxelAtLocalPosition:p].type);
        } else {
            XCTAssertEqual([chunk voxelAtLocalPosition:p].type, [modifiedChunk voxelAtLocalPosition:p].type);
        }
    }
    
    GSVoxel block = [modifiedChunk voxelAtLocalPosition:GSMakeIntegerVector3(2, 1, 2)];
    XCTAssertEqual(block.type, empty.type);
}

@end
