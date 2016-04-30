//
//  GSGridLRUTests.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/29/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GSGridLRU.h"
#import "GSGridBucket.h"

@interface GSGridLRUTests : XCTestCase

@end

@implementation GSGridLRUTests
{
    GSGridLRU *lru;
    NSString *a, *b, *c;
    GSGridBucket *bucketA, *bucketB, *bucketC;
}

- (void)setUp
{
    [super setUp];
    
    lru = [[GSGridLRU alloc] init];
    
    a=@"a";
    b=@"b";
    c=@"c";
    bucketA = [[GSGridBucket alloc] initWithName:@"a"];
    bucketB = [[GSGridBucket alloc] initWithName:@"b"];
    bucketC = [[GSGridBucket alloc] initWithName:@"c"];

    [lru referenceObject:a bucket:bucketA];
    [lru referenceObject:b bucket:bucketB];
    [lru referenceObject:c bucket:bucketC];
}

- (void)testBasicFunctionality
{
    NSString *object = nil;
    GSGridBucket *bucket = nil;
    BOOL r = NO;
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, a);
    XCTAssertEqualObjects(bucket, bucketA);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqual(object, b);
    XCTAssertEqual(bucket, bucketB);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, c);
    XCTAssertEqualObjects(bucket, bucketC);
    
    object = nil;
    bucket = nil;
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertFalse(r);
    XCTAssertEqualObjects(object, nil);
    XCTAssertEqualObjects(bucket, nil);
}

- (void)testRemoveObject
{
    NSString *object = nil;
    GSGridBucket *bucket = nil;
    BOOL r = NO;
    
    [lru removeObject:b];
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, a);
    XCTAssertEqualObjects(bucket, bucketA);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, c);
    XCTAssertEqualObjects(bucket, bucketC);
    
    object = nil;
    bucket = nil;
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertFalse(r);
    XCTAssertEqualObjects(object, nil);
    XCTAssertEqualObjects(bucket, nil);
}

- (void)testRemoveAllObjects
{
    NSString *object = nil;
    GSGridBucket *bucket = nil;
    BOOL r = NO;
    
    [lru removeAllObjects];
    
    object = nil;
    bucket = nil;
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertFalse(r);
    XCTAssertEqualObjects(object, nil);
    XCTAssertEqualObjects(bucket, nil);
}

- (void)testRemoveInvalidObject
{
    NSString *object = nil;
    GSGridBucket *bucket = nil;
    BOOL r = NO;
    
    [lru removeObject:@"z"];
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, a);
    XCTAssertEqualObjects(bucket, bucketA);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqual(object, b);
    XCTAssertEqual(bucket, bucketB);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, c);
    XCTAssertEqualObjects(bucket, bucketC);
    
    object = nil;
    bucket = nil;
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertFalse(r);
    XCTAssertEqualObjects(object, nil);
    XCTAssertEqualObjects(bucket, nil);
}

- (void)testUseReferenceToReorderList
{
    NSString *object = nil;
    GSGridBucket *bucket = nil;
    BOOL r = NO;
    
    [lru referenceObject:a bucket:bucketA];
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqual(object, b);
    XCTAssertEqual(bucket, bucketB);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, c);
    XCTAssertEqualObjects(bucket, bucketC);
    
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertTrue(r);
    XCTAssertEqualObjects(object, a);
    XCTAssertEqualObjects(bucket, bucketA);
    
    object = nil;
    bucket = nil;
    r = [lru popAndReturnObject:&object bucket:&bucket];
    XCTAssertFalse(r);
    XCTAssertEqualObjects(object, nil);
    XCTAssertEqualObjects(bucket, nil);
}

@end
