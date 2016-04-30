//
//  GSGridSlotTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/29/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSGridSlot.h"
#import "GSReaderWriterLock.h"



@interface GSFakeGridItem : NSObject <GSGridItem>

@property (readonly, nonatomic) vector_float3 minP;

- (void)invalidate;

@end

@implementation GSFakeGridItem

- (nonnull instancetype)copyWithZone:(NSZone *)zone
{
    return self;
}

- (void)invalidate
{
    // do nothing
}

@end



@interface GSGridSlotTests : XCTestCase

@end

@implementation GSGridSlotTests

- (void)testWrite
{
    GSFakeGridItem *myItem = [[GSFakeGridItem alloc] init];
    vector_float3 p = {1, 2, 3};
    GSGridSlot *slot = [[GSGridSlot alloc] initWithMinP:p];
    
    XCTAssertThrows(slot.item = myItem);

    [slot.lock lockForWriting];
    slot.item = myItem;
    [slot.lock unlockForWriting];
}

@end
