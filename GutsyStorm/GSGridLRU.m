//
//  GSGridLRU.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSGridLRU.h"

@implementation GSGridLRU
{
    NSMutableArray<NSObject<NSCopying> *> *_list;
    NSMutableDictionary<NSObject<NSCopying> *, NSNumber *> *_dictIndex;
    NSMutableDictionary<NSObject<NSCopying> *, GSGridBucket *> *_dictBucket;
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

- (void)referenceObject:(nonnull NSObject<NSCopying> *)object bucket:(nonnull GSGridBucket *)bucket
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

- (void)popAndReturnObject:(NSObject<NSCopying> * _Nonnull * _Nullable)outObject
                    bucket:(GSGridBucket * _Nonnull * _Nullable)outBucket
{
    NSParameterAssert(outObject);
    NSParameterAssert(outBucket);
    
    NSObject<NSCopying> *object = [_list lastObject];
    
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

- (void)removeObject:(nonnull NSObject<NSCopying> *)object
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