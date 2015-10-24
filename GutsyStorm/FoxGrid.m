//
//  FoxGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import "FoxVectorUtils.h" // for vector_hash
#import "FoxIntegerVector3.h"
#import "FoxVoxel.h"
#import "FoxGrid.h"
#import "FoxReaderWriterLock.h"
#import "FoxBoxedVector.h"


@interface FoxGrid ()

- (NSObject <FoxGridItem> *)searchForItemAtPosition:(vector_float3)minP
                                             bucket:(NSMutableArray<NSObject <FoxGridItem> *> *)bucket;

@end


@implementation FoxGrid
{
    FoxReaderWriterLock *_lockTheTableItself; // Lock protects the "buckets" array itself, but not its contents.

    NSUInteger _numBuckets;
    NSMutableArray<NSObject <FoxGridItem> *> * __strong *_buckets;

    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    int32_t _n;
    float _loadLevelToTriggerResize;
    
    fox_grid_item_factory_t _factory;

    NSMutableArray<FoxGrid *> *_dependentGrids;
    NSMutableDictionary *_mappingToDependentGrids;
}

- (instancetype)init
{
    assert(!"call -initWithFactory: instead");
    @throw nil;
}

- (instancetype)initWithName:(NSString *)name
                     factory:(fox_grid_item_factory_t)factory
{
    if (self = [super init]) {
        _factory = [factory copy];
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 2;
        _numBuckets = 1024;
        _n = 0;
        _loadLevelToTriggerResize = 0.80;
        _dependentGrids = [NSMutableArray<FoxGrid *> new];
        _mappingToDependentGrids = [NSMutableDictionary new];

        _buckets = (NSMutableArray<NSObject <FoxGridItem> *> * __strong *)
            calloc(_numBuckets, sizeof(NSMutableArray<NSObject <FoxGridItem> *> *));
        for(NSUInteger i=0; i<_numBuckets; ++i)
        {
            _buckets[i] = [NSMutableArray<NSObject <FoxGridItem> *> new];
        }

        _locks = (NSLock * __strong *)calloc(_numLocks, sizeof(NSLock *));
        for(NSUInteger i=0; i<_numLocks; ++i)
        {
            _locks[i] = [NSLock new];
            _locks[i].name = [NSString stringWithFormat:@"%u", (unsigned)i];
        }

        _lockTheTableItself = [FoxReaderWriterLock new];
        _lockTheTableItself.name = [NSString stringWithFormat:@"%@", name];
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
}

- (void)resizeTable
{
    [_lockTheTableItself lockForWriting];

    _n = 0;

    NSUInteger oldNumBuckets = _numBuckets;
    NSMutableArray<NSObject <FoxGridItem> *> * __strong *oldBuckets = _buckets;

    // Allocate memory for a new set of buckets.
    _numBuckets *= 2;
    assert(_numBuckets>0);
    _buckets = (NSMutableArray<NSObject <FoxGridItem> *> * __strong *)
        calloc(_numBuckets, sizeof(NSMutableArray<NSObject <FoxGridItem> *> *));
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        _buckets[i] = [NSMutableArray new];
    }

    // Insert each object into the new hash table.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        for(NSObject <FoxGridItem> *item in oldBuckets[i])
        {
            NSUInteger hash = vector_hash(item.minP);
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

- (BOOL)objectAtPoint:(vector_float3)p
             blocking:(BOOL)blocking
               object:(id _Nonnull * _Nullable)item
      createIfMissing:(BOOL)createIfMissing
        didCreateItem:(nullable BOOL *)outDidCreateItem
{
    if(blocking) {
        [_lockTheTableItself lockForReading];
    } else if(![_lockTheTableItself tryLockForReading]) {
        return NO;
    }

    BOOL result = NO;
    BOOL createdAnItem = NO;
    float load = 0;
    NSObject <FoxGridItem> * anObject = nil;
    vector_float3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <FoxGridItem> *> *bucket = _buckets[idxBucket];

    if(blocking) {
        [lock lock];
    } else if(![lock tryLock]) {
        [_lockTheTableItself unlockForReading];
        return NO;
    }

    anObject = [self searchForItemAtPosition:minP bucket:bucket];

    if(!anObject && createIfMissing) {
        anObject = _factory(minP);
        assert(anObject);
        [bucket addObject:anObject];
        OSAtomicIncrement32Barrier(&_n);
        load = (float)_n / _numBuckets;
        createdAnItem = YES;
    }

    if(anObject) {
        result = YES;
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    if(load > _loadLevelToTriggerResize) {
        [self resizeTable];
    }

    if (result) {
        if (item) {
            *item = anObject;
        }
        
        if (outDidCreateItem) {
            *outDidCreateItem = createdAnItem;
        }
    }

    return result;
}

- (id)objectAtPoint:(vector_float3)p
{
    id anItem = nil;
    [self objectAtPoint:p
               blocking:YES
                 object:&anItem
        createIfMissing:YES
          didCreateItem:nil];
    assert(anItem);
    return anItem;
}

- (void)evictItemAtPoint:(vector_float3)p
{
    [_lockTheTableItself lockForReading];

    vector_float3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <FoxGridItem> *> *bucket = _buckets[idxBucket];

    [lock lock];

    NSObject <FoxGridItem> *foundItem = [self searchForItemAtPosition:minP bucket:bucket];

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
        [_buckets[i] enumerateObjectsUsingBlock:^(NSObject <FoxGridItem> *item, NSUInteger idx, BOOL *stop) {
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

- (NSObject <FoxGridItem> *)searchForItemAtPosition:(vector_float3)minP
                                             bucket:(NSMutableArray<NSObject <FoxGridItem> *> *)bucket
{
    assert(bucket);

    for(NSObject <FoxGridItem> *item in bucket)
    {
        assert(item);
        if(vector_equal(item.minP, minP)) {
            return item;
        }
    }

    return nil;
}

- (void)invalidateItemWithChange:(FoxGridEdit *)change
{
    // Invalidate asynchronously to avoid deadlock.
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [_lockTheTableItself lockForReading];

        vector_float3 pos = change.pos;
        vector_float3 minP = MinCornerForChunkAtPoint(pos);
        NSUInteger hash = vector_hash(minP);
        NSUInteger idxBucket = hash % _numBuckets;
        NSUInteger idxLock = hash % _numLocks;
        NSLock *lock = _locks[idxLock];
        NSMutableArray<NSObject <FoxGridItem> *> *bucket = _buckets[idxBucket];

        [lock lock];

        NSObject <FoxGridItem> *foundItem = nil;

        foundItem = [self searchForItemAtPosition:minP bucket:bucket];

        if(foundItem && [foundItem respondsToSelector:@selector(itemWillBeInvalidated)]) {
            [foundItem itemWillBeInvalidated];
        }

        [self willInvalidateItem:foundItem atPoint:minP];

        if(foundItem) {
            [bucket removeObject:foundItem];
        }

        [self invalidateItemsInDependentGridsWithChange:change];

        [lock unlock];
        [_lockTheTableItself unlockForReading];
    });
}

- (void)willInvalidateItem:(NSObject <FoxGridItem> *)item atPoint:(vector_float3)p
{
    // do nothing
}

- (void)invalidateItemsInDependentGridsWithChange:(FoxGridEdit *)change
{
    assert(change);

    for(FoxGrid *grid in _dependentGrids)
    {
        NSSet * (^mapping)(FoxGridEdit *) = [_mappingToDependentGrids objectForKey:[grid description]];
        NSSet *correspondingPoints = mapping(change);
        for(FoxBoxedVector *q in correspondingPoints)
        {
            FoxGridEdit *secondaryChange = [[FoxGridEdit alloc] initWithOriginalItem:nil
                                                                        modifiedItem:nil
                                                                                 pos:[q vectorValue]];
            [grid invalidateItemWithChange:secondaryChange];
        }
    }
}

- (void)registerDependentGrid:(FoxGrid *)grid mapping:(NSSet<FoxBoxedVector *> * (^)(FoxGridEdit *))mapping
{
    [_dependentGrids addObject:grid];
    [_mappingToDependentGrids setObject:[mapping copy] forKey:[grid description]];
}

- (void)replaceItemAtPoint:(vector_float3)p
                 transform:(NSObject <FoxGridItem> * (^)(NSObject <FoxGridItem> *original))newReplacementItem
{
    [_lockTheTableItself lockForReading];

    vector_float3 minP = MinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <FoxGridItem> *> *bucket = _buckets[idxBucket];

    [lock lock];

    // Search for an existing item at the specified point. If it exists then just do a straight-up replacement.
    for(NSUInteger i = 0, n = bucket.count; i < n; ++i)
    {
        NSObject <FoxGridItem> *item = [bucket objectAtIndex:i];

        if(vector_equal(item.minP, minP)) {
            NSObject <FoxGridItem> *replacement = newReplacementItem(item);
            if([item respondsToSelector:@selector(itemWillBeInvalidated)]) {
                [item itemWillBeInvalidated];
            }
            [bucket replaceObjectAtIndex:i withObject:replacement];
            
            FoxGridEdit *change = [[FoxGridEdit alloc] initWithOriginalItem:item
                                                           modifiedItem:replacement
                                                                    pos:p];

            [self invalidateItemsInDependentGridsWithChange:change];

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