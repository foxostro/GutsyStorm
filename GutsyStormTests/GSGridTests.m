//
//  GSGridTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/29/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSGrid.h"
#import "GSGridSlot.h"
#import "GSVoxel.h"
#import "GSVectorUtils.h"

@interface GSGridTests : XCTestCase

@end

@implementation GSGridTests

- (void)testBasicFunctionality
{
    vector_float3 p;

    GSGrid *grid = [[GSGrid alloc] initWithName:@"unittest"];
    
    p = vector_make(0, 0, 0);
    GSGridSlot *slot1 = [grid slotAtPoint:p];
    XCTAssertTrue(vector_equal(slot1.minP, GSMinCornerForChunkAtPoint(p)));
    
    p = vector_make(CHUNK_SIZE_X, CHUNK_SIZE_Y-1, 0);
    GSGridSlot *slot2 = [grid slotAtPoint:p];
    XCTAssertTrue(vector_equal(slot2.minP, GSMinCornerForChunkAtPoint(p)));
    XCTAssertNotEqual(slot1, slot2);
    
    XCTAssertEqual(2, grid.count);
    
    [grid evictAllItems];
    
    XCTAssertEqual(0, grid.count);
}

@end
