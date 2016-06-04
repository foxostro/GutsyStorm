//
//  GSGridLRU.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSGridLRU.h"


struct GSGridLRUList {
    struct GSGridLRUList *prev, *next;
    __unsafe_unretained NSObject<NSCopying> *object;
};


@implementation GSGridLRU
{
    struct GSGridLRUList *_head, *_tail;
    NSMutableDictionary<NSObject<NSCopying> *, NSValue *> *_dictFastLookup;
    NSMutableDictionary<NSObject<NSCopying> *, GSGridBucket *> *_dictBucket;
}

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _head = NULL;
        _tail = NULL;
        _dictFastLookup = [NSMutableDictionary new];
        _dictBucket = [NSMutableDictionary new];
    }
    return self;
}

- (void)dealloc
{
    [self removeAllObjects];
}

- (void)referenceObject:(nonnull NSObject<NSCopying> *)object bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(object);
    NSParameterAssert(bucket);
    
    struct GSGridLRUList *node;
    NSValue *boxedNode = [_dictFastLookup objectForKey:object];

    if (boxedNode) {
        node = [boxedNode pointerValue];
        assert(node);

        // Remove the node from it's current position in the list.
        if (node == _head) {
            _head = _head->next;
        }
        if (node == _tail) {
            _tail = _tail->prev;
        }
        if (node->next) {
            node->next->prev = node->prev;
        }
    } else {
        node = calloc(sizeof(struct GSGridLRUList), 1);
        node->object = object;
    }
    
    // Insert the node at the beginning of the list. It becomes the new head.
    node->prev = NULL;
    node->next = _head;
    if (_head) {
        _head->prev = node;
    }
    if (!_tail) {
        _tail = node;
    }
    _head = node;
    
    [_dictFastLookup setObject:[NSValue valueWithPointer:node] forKey:object];
    [_dictBucket setObject:bucket forKey:object];
}

- (BOOL)popAndReturnObject:(NSObject<NSCopying> * _Nonnull * _Nullable)outObject
                    bucket:(GSGridBucket * _Nonnull * _Nullable)outBucket
{
    NSParameterAssert(outObject);
    NSParameterAssert(outBucket);
    
    if (!_tail) {
        return NO;
    }

    NSObject<NSCopying> *object = _tail->object;
    assert(object);

    GSGridBucket *bucket = [_dictBucket objectForKey:object];
    
    // Remove the tail item from the list.
    struct GSGridLRUList *node = _tail;
    if (_tail->prev) {
        _tail->prev->next = NULL;
    }
    _tail = _tail->prev;
    if (node == _head) {
        _head = _tail;
    }
    free(node);

    [_dictFastLookup removeObjectForKey:object];
    [_dictBucket removeObjectForKey:object];

    *outObject = object;
    *outBucket = bucket;
    return YES;
}

- (void)removeObject:(nonnull NSObject<NSCopying> *)object
{
    NSParameterAssert(object);

    NSValue *boxedNode = [_dictFastLookup objectForKey:object];
    
    if (boxedNode) {
        struct GSGridLRUList *node = [boxedNode pointerValue];
        assert(node);

        // Remove the node from it's current position in the list.
        if (node == _head) {
            _head = _head->next;
        }
        if (node == _tail) {
            _tail = node->prev;
        }
        if (node->next) {
            node->next->prev = node->prev;
        }
        free(node);
    }

    [_dictFastLookup removeObjectForKey:object];
    [_dictBucket removeObjectForKey:object];
}

- (void)removeAllObjects
{
    struct GSGridLRUList *node = _head;

    while(node)
    {
        struct GSGridLRUList *tofree = node;
        node = node->next;
        free(tofree);
    }

    _head = NULL;
    _tail = NULL;

    [_dictFastLookup removeAllObjects];
    [_dictBucket removeAllObjects];
}

@end