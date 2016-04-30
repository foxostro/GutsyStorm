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
    NSMutableDictionary<NSObject<NSCopying> *, GSGridBucket *> *_dictBucket;
}

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _list = [NSMutableArray new];
        _dictBucket = [NSMutableDictionary new];
    }
    return self;
}

- (void)referenceObject:(nonnull NSObject<NSCopying> *)object bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(object);
    NSParameterAssert(bucket);

    NSUInteger index = [_list indexOfObject:object];

    if (NSNotFound != index) {
        [_list removeObjectAtIndex:index];
    }

    [_list insertObject:object atIndex:0];
    [_dictBucket setObject:bucket forKey:object];
}

- (BOOL)popAndReturnObject:(NSObject<NSCopying> * _Nonnull * _Nullable)outObject
                    bucket:(GSGridBucket * _Nonnull * _Nullable)outBucket
{
    NSParameterAssert(outObject);
    NSParameterAssert(outBucket);
    
    NSObject<NSCopying> *object = [_list lastObject];
    
    if (!object) {
        return NO;
    }

    GSGridBucket *bucket = [_dictBucket objectForKey:object];

    [_list removeLastObject];
    [_dictBucket removeObjectForKey:object];

    *outObject = object;
    *outBucket = bucket;
    return YES;
}

- (void)removeObject:(nonnull NSObject<NSCopying> *)object
{
    NSParameterAssert(object);
    
    NSUInteger index = [_list indexOfObject:object];
    
    if (NSNotFound != index) {
        [_list removeObjectAtIndex:index];
    }

    [_dictBucket removeObjectForKey:object];
}

- (void)removeAllObjects
{
    [_list removeAllObjects];
    [_dictBucket removeAllObjects];
}

@end