//
//  GSNewGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKVector3.h>
#import <GLKit/GLKQuaternion.h>
#import "GLKVector3Extra.h"
#import "GSIntegerVector3.h"
#import "Voxel.h"
#import "GSGrid.h"
#import "GSReaderWriterLock.h"
#import "GSBoxedVector.h"


@interface GSGrid ()

- (NSObject <GSGridItem> *)searchForItemAtPosition:(GLKVector3)minP bucket:(NSMutableArray *)bucket;

@end


@implementation GSGrid
{
    GSReaderWriterLock *_lockTheTableItself; // Lock protects the "buckets" array itself, but not its contents.

    NSUInteger _numBuckets;
    NSMutableArray * __strong *_buckets;

    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    int32_t _n;
    float _loadLevelToTriggerResize;
    
    grid_item_factory_t _factory;

    NSMutableArray *_dependentGrids;
    NSMutableDictionary *_mappingToDependentGrids;
    
    dispatch_queue_t _queue;
    dispatch_group_t _group; // all queue blocks are placed in a group so we can flush the queue at shutdown
    BOOL _cancelPendingCreation;
}

- (id)init
{
    assert(!"call -initWithFactory: instead");
    return nil;
}

- (id)initWithFactory:(grid_item_factory_t)factory
{
    if(self = [super init]) {
        _factory = [factory copy];
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 2;
        _numBuckets = 1024;
        _n = 0;
        _loadLevelToTriggerResize = 0.80;
        _dependentGrids = [[NSMutableArray alloc] init];
        _mappingToDependentGrids = [[NSMutableDictionary alloc] init];
        _cancelPendingCreation = NO;

        _buckets = (NSMutableArray * __strong *)calloc(_numBuckets, sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<_numBuckets; ++i)
        {
            _buckets[i] = [[NSMutableArray alloc] init];
        }

        _locks = (NSLock * __strong *)calloc(_numLocks, sizeof(NSLock *));
        for(NSUInteger i=0; i<_numLocks; ++i)
        {
            _locks[i] = [[NSLock alloc] init];
        }

        _lockTheTableItself = [[GSReaderWriterLock alloc] init];
        
        _queue = dispatch_queue_create("com.foxostro.GutsyStorm.GSGrid", DISPATCH_QUEUE_CONCURRENT);
        _group = dispatch_group_create();
    }

    return self;
}

- (void)dealloc
{
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        _buckets[i] = nil;
    }
    free(_buckets);

    for(NSUInteger i=0; i<_numLocks; ++i)
    {
        _locks[i] = nil;
    }
    free(_locks);
    
    dispatch_release(_queue);
    dispatch_release(_group);
}

- (void)shutdown
{
    _cancelPendingCreation = YES;
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

- (void)resizeTable
{
    [_lockTheTableItself lockForWriting];

    _n = 0;

    NSUInteger oldNumBuckets = _numBuckets;
    NSMutableArray * __strong *oldBuckets = _buckets;

    // Allocate memory for a new set of buckets.
    _numBuckets *= 2;
    assert(_numBuckets>0);
    _buckets = (NSMutableArray * __strong *)calloc(_numBuckets, sizeof(NSMutableArray *));
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        _buckets[i] = [[NSMutableArray alloc] init];
    }

    // Insert each object into the new hash table.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        for(NSObject <GSGridItem> *item in oldBuckets[i])
        {
            NSUInteger hash = GLKVector3Hash(item.minP);
            [_buckets[hash % _numBuckets] addObject:item];
            _n++;
        }
    }

    [_lockTheTableItself unlockForWriting];

    // Free the old set of buckets.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        oldBuckets[i] = nil;
    }
    free(oldBuckets);
}

- (BOOL)objectAtPoint:(GLKVector3)p
             blocking:(BOOL)blocking
               object:(id *)item
      createIfMissing:(BOOL)createIfMissing
     allowAsyncCreate:(BOOL)allowAsyncCreate
{
    if(blocking) {
        [_lockTheTableItself lockForReading];
    } else if(![_lockTheTableItself tryLockForReading]) {
        return NO;
    }

    BOOL result = NO;
    float load = 0;
    NSObject <GSGridItem> * anObject = nil;
    GLKVector3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray *bucket = _buckets[idxBucket];

    if(blocking) {
        [lock lock];
    } else if(![lock tryLock]) {
        [_lockTheTableItself unlockForReading];
        return NO;
    }

    anObject = [self searchForItemAtPosition:minP bucket:bucket];

    if(!anObject && createIfMissing) {
        if(allowAsyncCreate) {
            dispatch_group_async(_group, _queue, ^{
                // create the object at some later time
                if(_cancelPendingCreation) return;
                [self objectAtPoint:p
                           blocking:NO
                             object:nil // we don't want the object returned to us, really
                    createIfMissing:YES
                   allowAsyncCreate:NO]; // of course, we can't defer again
            });
        } else {
            anObject = _factory(minP);
            assert(anObject);
            [bucket addObject:anObject];
            OSAtomicIncrement32Barrier(&_n);
            load = (float)_n / _numBuckets;
        }
    }

    if(anObject) {
        result = YES;
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    if(load > _loadLevelToTriggerResize) {
        [self resizeTable];
    }

    if(result && item) {
        *item = anObject;
    }
    return result;
}

- (id)objectAtPoint:(GLKVector3)p
{
    id anItem = nil;
    [self objectAtPoint:p
               blocking:YES
                 object:&anItem
        createIfMissing:YES
       allowAsyncCreate:NO];
    assert(anItem);
    return anItem;
}

- (void)evictItemAtPoint:(GLKVector3)p
{
    [_lockTheTableItself lockForReading];

    GLKVector3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray *bucket = _buckets[idxBucket];

    [lock lock];

    NSObject <GSGridItem> *foundItem = [self searchForItemAtPosition:minP bucket:bucket];

    if(foundItem) {
        if([foundItem respondsToSelector:@selector(itemWillBeEvicted)]) {
            [foundItem itemWillBeEvicted];
        }
        [bucket removeObject:foundItem];
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];
}

- (void)evictAllItems
{
    [_lockTheTableItself lockForWriting]; // take the global lock to prevent reading from any stripe

    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        [_buckets[i] enumerateObjectsUsingBlock:^(NSObject <GSGridItem> *item, NSUInteger idx, BOOL *stop) {
            if([item respondsToSelector:@selector(itemWillBeEvicted)]) {
                [item itemWillBeEvicted];
            }
        }];
    }

    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        [_buckets[i] removeAllObjects];
    }

    [_lockTheTableItself unlockForWriting];
}

- (NSObject <GSGridItem> *)searchForItemAtPosition:(GLKVector3)minP bucket:(NSMutableArray *)bucket
{
    assert(bucket);

    for(NSObject <GSGridItem> *item in bucket)
    {
        assert(item);
        if(GLKVector3AllEqualToVector3(item.minP, minP)) {
            return item;
        }
    }

    return nil;
}

- (void)invalidateItemAtPoint:(GLKVector3)p
{
    // Invalidate asynchronously to avoid deadlock.
    dispatch_group_async(_group, _queue, ^{
        [_lockTheTableItself lockForReading];

        GLKVector3 minP = MinCornerForChunkAtPoint(p);
        NSUInteger hash = GLKVector3Hash(minP);
        NSUInteger idxBucket = hash % _numBuckets;
        NSUInteger idxLock = hash % _numLocks;
        NSLock *lock = _locks[idxLock];
        NSMutableArray *bucket = _buckets[idxBucket];

        [lock lock];

        NSObject <GSGridItem> *foundItem = nil;

        foundItem = [self searchForItemAtPosition:minP bucket:bucket];

        if(foundItem && [foundItem respondsToSelector:@selector(itemWillBeInvalidated)]) {
            [foundItem itemWillBeInvalidated];
        }

        [self willInvalidateItem:foundItem atPoint:minP];

        if(foundItem) {
            [bucket removeObject:foundItem];
        }
        
        [self invalidateItemsDependentOnItemAtPoint:minP];
        
        [lock unlock];
        [_lockTheTableItself unlockForReading];
    });
}

- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(GLKVector3)p
{
    // do nothing
}

- (void)invalidateItemsDependentOnItemAtPoint:(GLKVector3)p
{
    for(GSGrid *grid in _dependentGrids)
    {
        NSSet * (^mapping)(GLKVector3) = [_mappingToDependentGrids objectForKey:[grid description]];
        NSSet *correspondingPoints = mapping(p);
        for(GSBoxedVector *q in correspondingPoints)
        {
            [grid invalidateItemAtPoint:[q vectorValue]];
        }
    }
}

- (void)registerDependentGrid:(GSGrid *)grid
                      mapping:(NSSet * (^)(GLKVector3))mapping
{
    [_dependentGrids addObject:grid];
    [_mappingToDependentGrids setObject:[mapping copy] forKey:[grid description]];
}

- (void)replaceItemAtPoint:(GLKVector3)p
                 transform:(NSObject <GSGridItem> * (^)(NSObject <GSGridItem> *original))newReplacementItem
{
    [_lockTheTableItself lockForReading];

    GLKVector3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray *bucket = _buckets[idxBucket];

    [lock lock];

    // Search for an existing item at the specified point. If it exists then just do a straight-up replacement.
    for(NSObject <GSGridItem> *item in bucket)
    {
        if(GLKVector3AllEqualToVector3(item.minP, minP)) {
            NSObject <GSGridItem> *replacement = newReplacementItem(item);
            if([item respondsToSelector:@selector(itemWillBeInvalidated)]) {
                [item itemWillBeInvalidated];
            }
            [bucket removeObject:item];
            [bucket addObject:replacement];

            [self invalidateItemsDependentOnItemAtPoint:p];

            [lock unlock];
            [_lockTheTableItself unlockForReading];
            return;
        }
    }

    // If the item does not already exist in the cache then have the factory retrieve/create it, transform, and add to the cache.
    [bucket addObject:newReplacementItem(_factory(minP))];
    OSAtomicIncrement32Barrier(&_n);
    float load = (float)_n / _numBuckets;

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    if(load > _loadLevelToTriggerResize) {
        [self resizeTable];
    }
}

@end