//
//  GSGridItemLRU.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSGridItemLRU.h"

@implementation GSGridItemLRU
{
    NSMutableArray<NSObject<GSGridItem> *> *_list;
    NSMutableDictionary<NSObject<GSGridItem> *, NSNumber *> *_dictIndex;
    NSMutableDictionary<NSObject<GSGridItem> *, GSGridBucket *> *_dictBucket;
}

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _list = [NSMutableArray new];
        _dictIndex = [NSMutableDictionary new];
        _dictBucket = [NSMutableDictionary new];
    }
    return self;
}

- (void)referenceObject:(nonnull NSObject<GSGridItem> *)object bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(object);
    NSParameterAssert(bucket);

    NSNumber *indexNumber = [_dictIndex objectForKey:object];
    if (indexNumber) {
        NSUInteger index = [indexNumber unsignedIntegerValue];
        [_list removeObjectAtIndex:index];
    }

    [_list insertObject:object atIndex:0];
    [_dictIndex setObject:@(0) forKey:object];
    [_dictBucket setObject:bucket forKey:object];
}

- (void)popAndReturnObject:(id _Nonnull * _Nonnull)outObject bucket:(id _Nonnull * _Nonnull)outBucket
{
    NSParameterAssert(outObject);
    NSParameterAssert(outBucket);
    
    NSObject<GSGridItem> *object = [_list lastObject];
    
    if (!object) {
        return;
    }

    GSGridBucket *bucket = [_dictBucket objectForKey:object];

    [_list removeLastObject];
    [_dictBucket removeObjectForKey:object];
    [_dictIndex removeObjectForKey:object];

    *outObject = object;
    *outBucket = bucket;
}

- (void)removeObject:(nonnull NSObject<GSGridItem> *)object
{
    NSParameterAssert(object);
    
    NSNumber *indexNumber = [_dictIndex objectForKey:object];
    if (indexNumber) {
        NSUInteger index = [indexNumber unsignedIntegerValue];
        [_list removeObjectAtIndex:index];
        [_dictIndex removeObjectForKey:object];
        [_dictBucket removeObjectForKey:object];
    }
}

- (void)removeAllObjects
{
    [_list removeAllObjects];
    [_dictIndex removeAllObjects];
    [_dictBucket removeAllObjects];
}

@end