//
//  GSChunkSunlightDataTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/29/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSTerrainJournal.h"
#import "GSChunkVoxelData.h"
#import "GSChunkSunlightData.h"
#import "GSVoxelNeighborhood.h"
#import "GSTerrainBuffer.h"
#import "GSTerrainGenerator.h"
#import "GSBox.h"
#import "GSVectorUtils.h"


@interface GSChunkSunlightDataTests_TerrainGenerator : GSTerrainGenerator
@end

@implementation GSChunkSunlightDataTests_TerrainGenerator

- (void)generateWithDestination:(nonnull GSVoxel *)voxels
                          count:(NSUInteger)count
                         region:(nonnull GSIntAABB *)box
                  offsetToWorld:(vector_float3)offsetToWorld
{
    vector_long3 clp;
    FOR_BOX(clp, *box)
    {
        BOOL isEmpty = YES;
        
        if (clp.y == 32) {
            BOOL centerChunk = (offsetToWorld.x == 0 && offsetToWorld.y == 0 && offsetToWorld.z == 0);
            isEmpty = (centerChunk && clp.x == 7 && clp.z == 7);
        } else if (clp.y == 0 || clp.y == 10) {
            isEmpty = NO;
        }
        
        NSUInteger idx = INDEX_BOX(clp, *box);
        voxels[idx].type = isEmpty ? VOXEL_TYPE_EMPTY : VOXEL_TYPE_GROUND;
        voxels[idx].opaque = isEmpty ? 0 : 1;
    }
}

@end


@interface GSChunkSunlightDataTests : XCTestCase

@end

@implementation GSChunkSunlightDataTests
{
    dispatch_group_t groupForSaving;
    dispatch_queue_t queueForSaving;
    GSTerrainJournal *journal;
    GSChunkSunlightData *sunChunk;
}

- (void)setUp
{
    [super setUp];

    groupForSaving = dispatch_group_create();
    queueForSaving = dispatch_queue_create("queueForSaving", DISPATCH_QUEUE_SERIAL);
    
    journal = [[GSTerrainJournal alloc] init];
    
    GSTerrainGenerator *generator = [[GSChunkSunlightDataTests_TerrainGenerator alloc] initWithRandomSeed:0];
    
    GSVoxelNeighborhood *neighborhood = [[GSVoxelNeighborhood alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 p = [GSNeighborhood offsetForNeighborIndex:i];
        GSChunkVoxelData *voxels = [[GSChunkVoxelData alloc] initWithMinP:GSMinCornerForChunkAtPoint(p)
                                                                   folder:nil
                                                           groupForSaving:groupForSaving
                                                           queueForSaving:queueForSaving
                                                                  journal:journal
                                                                generator:generator
                                                             allowLoading:NO];
        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }

    sunChunk = [[GSChunkSunlightData alloc] initWithMinP:vector_make(0, 0, 0)
                                                  folder:nil
                                          groupForSaving:groupForSaving
                                          queueForSaving:queueForSaving
                                            neighborhood:neighborhood
                                            allowLoading:NO];
}

- (NSMutableString *)stringSliceOf:(nonnull GSChunkSunlightData *)chunk atY:(int)y
{
    GSTerrainBufferElement v;
    vector_long3 p;
    NSMutableString *slice = [[NSMutableString alloc] init];

    for(int z=0; z<CHUNK_SIZE_Z; ++z)
    {
        [slice appendFormat:@"\n"];
        for(int x=0; x<CHUNK_SIZE_X; ++x)
        {
            p = GSMakeIntegerVector3(x, y, z);
            v = [chunk.sunlight valueAtPosition:p];
            [slice appendFormat:@"%x", v];
        }
    }

    return slice;
}

- (void)testSunlightMax
{
    // The expected values for tests in this suite expect that CHUNK_LIGHTING_MAX==12.
    XCTAssertEqual(12, CHUNK_LIGHTING_MAX);
}

- (void)testBasicSunlightGeneration
{
    vector_long3 p;
    GSTerrainBufferElement v;
    NSString *slice;

    p = GSMakeIntegerVector3(7, 1, 7);
    v = [sunChunk.sunlight valueAtPosition:p];
    XCTAssertEqual(v, 0);
    
    slice = [self stringSliceOf:sunChunk atY:1];
    NSString *expectedSlice1 =
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000";
    XCTAssertEqualObjects(slice, expectedSlice1);
    
    slice = [self stringSliceOf:sunChunk atY:11];
    NSString *expectedSlice11 =
    @"\n0001234543210000" \
    @"\n0012345654321000" \
    @"\n0123456765432100" \
    @"\n1234567876543210" \
    @"\n2345678987654321" \
    @"\n3456789a98765432" \
    @"\n456789aba9876543" \
    @"\n56789abcba987654" \
    @"\n456789aba9876543" \
    @"\n3456789a98765432" \
    @"\n2345678987654321" \
    @"\n1234567876543210" \
    @"\n0123456765432100" \
    @"\n0012345654321000" \
    @"\n0001234543210000" \
    @"\n0000123432100000";
    XCTAssertEqualObjects(slice, expectedSlice11);

    slice = [self stringSliceOf:sunChunk atY:30];
    NSString *expectedSlice30 =
    @"\n0001234543210000" \
    @"\n0012345654321000" \
    @"\n0123456765432100" \
    @"\n1234567876543210" \
    @"\n2345678987654321" \
    @"\n3456789a98765432" \
    @"\n456789aba9876543" \
    @"\n56789abcba987654" \
    @"\n456789aba9876543" \
    @"\n3456789a98765432" \
    @"\n2345678987654321" \
    @"\n1234567876543210" \
    @"\n0123456765432100" \
    @"\n0012345654321000" \
    @"\n0001234543210000" \
    @"\n0000123432100000";
    XCTAssertEqualObjects(slice, expectedSlice30);
    
    slice = [self stringSliceOf:sunChunk atY:33];
    NSString *expectedSlice33 =
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc" \
    @"\ncccccccccccccccc";
    XCTAssertEqualObjects(slice, expectedSlice33);
}

- (void)testCopyWithEdit
{
    // Make an edit to the voxels, generate a sunlight chunk in two different ways and check that they're the same.
    
    vector_long3 p = GSZeroIntVec3;
    GSIntAABB chunkBox = { GSZeroIntVec3, GSChunkSizeIntVec3 };

    GSChunkVoxelData *voxels1 = [sunChunk.neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    
    GSVoxel cube = {0};
    cube.type = VOXEL_TYPE_GROUND;
    cube.opaque = 1;
    GSChunkVoxelData *voxels2 = [voxels1 copyWithEditAtPoint:vector_make(7, 32, 7) block:cube operation:Set];
    
    p = GSMakeIntegerVector3(7, 32, 7);
    XCTAssertEqual([voxels1 voxelAtLocalPosition:p].opaque, 0);
    XCTAssertEqual([voxels2 voxelAtLocalPosition:p].opaque, 1);
    
    p = GSMakeIntegerVector3(7, 30, 7);
    XCTAssertEqual([voxels1 voxelAtLocalPosition:p].outside, 1);
    XCTAssertEqual([voxels2 voxelAtLocalPosition:p].outside, 0);

    GSVoxelNeighborhood *neighborhood = [sunChunk.neighborhood copyReplacing:voxels1 withNeighbor:voxels2];

    vector_long3 border = {1, 0, 1};
    GSIntAABB sliceBox = {
        .mins = -border,
        .maxs = border + GSChunkSizeIntVec3
    };
    GSTerrainBuffer *sunlight = [[neighborhood newSunlightBuffer] copySubBufferFromSubrange:&sliceBox];

    GSChunkSunlightData *sunChunk2 = [sunChunk copyReplacingSunlightData:sunlight neighborhood:neighborhood];
    GSChunkSunlightData *sunChunk3 = [[GSChunkSunlightData alloc] initWithMinP:vector_make(0, 0, 0)
                                                                        folder:nil
                                                                groupForSaving:groupForSaving
                                                                queueForSaving:queueForSaving
                                                                  neighborhood:neighborhood
                                                                  allowLoading:NO];

    FOR_BOX(p, chunkBox)
    {
        XCTAssertEqual([neighborhood voxelAtPoint:p].opaque, [voxels2 voxelAtLocalPosition:p].opaque);
        XCTAssertEqual([neighborhood voxelAtPoint:p].outside, [voxels2 voxelAtLocalPosition:p].outside);
        XCTAssertEqual([sunChunk2.sunlight valueAtPosition:p], [sunChunk3.sunlight valueAtPosition:p]);
    }
    
    NSString *slice = [self stringSliceOf:sunChunk3 atY:30];
    NSString *expectedSlice30 =
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000" \
    @"\n0000000000000000";
    XCTAssertEqualObjects(slice, expectedSlice30);
}

@end
