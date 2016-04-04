//
//  GSGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "GSVectorUtils.h" // for vector_hash
#import "GSIntegerVector3.h"
#import "GSVoxel.h"
#import "GSGrid.h"
#import "GSReaderWriterLock.h"
#import "GSBoxedVector.h"


@interface GSGrid ()

- (NSObject <GSGridItem> *)searchForItemAtPosition:(vector_float3)minP
                                            bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket;

@end


@implementation GSGrid
{
    GSReaderWriterLock *_lockTheTableItself; // Lock protects the "buckets" array itself, but not its contents.

    NSUInteger _numBuckets;
    NSMutableArray<NSObject <GSGridItem> *> * __strong *_buckets;

    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    NSLock *_lockTheCount;
    NSUInteger _count;
    float _loadLevelToTriggerResize;
    NSUInteger _costCount;
    NSUInteger _costLimit;
    
    GSGridItemFactory _factory;

    NSMutableArray<GSGrid *> *_dependentGrids;
    NSMutableDictionary *_mappingToDependentGrids;
}

- (nonnull instancetype)init
{
    assert(!"call -initWithFactory: instead");
    @throw nil;
}

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                             factory:(nonnull GSGridItemFactory)factory
{
    if (self = [super init]) {
        _factory = [factory copy];
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 2;
        _numBuckets = 1024;
        _dependentGrids = [NSMutableArray<GSGrid *> new];
        _mappingToDependentGrids = [NSMutableDictionary new];

        _lockTheCount = [NSLock new];
        _lockTheCount.name = @"lockTheCount";
        _count = 0;
        _costLimit = 0; // XXX: need to allow this to be specified
        _loadLevelToTriggerResize = 0.80;

        _buckets = (NSMutableArray<NSObject <GSGridItem> *> * __strong *)
            calloc(_numBuckets, sizeof(NSMutableArray<NSObject <GSGridItem> *> *));
        if (!_buckets) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating `_buckets'."];
        }
        for(NSUInteger i=0; i<_numBuckets; ++i)
        {
            _buckets[i] = [NSMutableArray<NSObject <GSGridItem> *> new];
        }

        _locks = (NSLock * __strong *)calloc(_numLocks, sizeof(NSLock *));
        if (!_locks) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating `_locks'."];
        }
        for(NSUInteger i=0; i<_numLocks; ++i)
        {
            _locks[i] = [NSLock new];
            _locks[i].name = [NSString stringWithFormat:@"%u", (unsigned)i];
        }

        _lockTheTableItself = [GSReaderWriterLock new];
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

    [_lockTheCount lock];
    _count = 0;
    _costCount = 0;
    [_lockTheCount unlock];

    NSUInteger oldNumBuckets = _numBuckets;
    NSMutableArray<NSObject <GSGridItem> *> * __strong *oldBuckets = _buckets;

    // Allocate memory for a new set of buckets.
    _numBuckets *= 2;
    assert(_numBuckets>0);
    _buckets = (NSMutableArray<NSObject <GSGridItem> *> * __strong *)
        calloc(_numBuckets, sizeof(NSMutableArray<NSObject <GSGridItem> *> *));
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        _buckets[i] = [NSMutableArray new];
    }

    // Insert each object into the new hash table.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        for(NSObject <GSGridItem> *item in oldBuckets[i])
        {
            NSUInteger hash = vector_hash(item.minP);
            [_buckets[hash % _numBuckets] addObject:item];

            [_lockTheCount lock];
            _count++;
            _costCount += item.cost;
            [_lockTheCount unlock];
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
    BOOL factoryDidFail = NO;
    float load = 0;
    NSObject <GSGridItem> * anObject = nil;
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[idxBucket];

    if(blocking) {
        [lock lock];
    } else if(![lock tryLock]) {
        [_lockTheTableItself unlockForReading];
        return NO;
    }

    anObject = [self searchForItemAtPosition:minP bucket:bucket];

    if(!anObject && createIfMissing) {
        anObject = _factory(minP);

        if (!anObject) {
            factoryDidFail = YES;

            if (!self.factoryMayFail) {
                [NSException raise:@"Out of Memory" format:@"Out of memory allocating `anObject' for GSGrid."];
            }
        } else {
        [bucket addObject:anObject];

            [_lockTheCount lock];
            _count++;
        _costCount += anObject.cost;
            load = (float)_count / _numBuckets;
            [_lockTheCount unlock];

        createdAnItem = YES;
    }
    }

    if(anObject) {
        result = YES;
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    if (factoryDidFail) {
        [self evictAllItems];
        return [self objectAtPoint:p
                          blocking:blocking
                            object:item
                   createIfMissing:createIfMissing
                     didCreateItem:outDidCreateItem];
    } else {
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
}

- (nonnull id)objectAtPoint:(vector_float3)p
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

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[idxBucket];

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

- (nullable NSObject <GSGridItem> *)searchForItemAtPosition:(vector_float3)minP
                                                     bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket
{
    assert(bucket);

    for(NSObject <GSGridItem> *item in bucket)
    {
        assert(item);
        if(vector_equal(item.minP, minP)) {
            return item;
        }
    }

    return nil;
}

- (void)invalidateItemWithChange:(nonnull GSGridEdit *)change
{
    // Invalidate asynchronously to avoid deadlock.
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [_lockTheTableItself lockForReading];

        vector_float3 pos = change.pos;
        vector_float3 minP = GSMinCornerForChunkAtPoint(pos);
        NSUInteger hash = vector_hash(minP);
        NSUInteger idxBucket = hash % _numBuckets;
        NSUInteger idxLock = hash % _numLocks;
        NSLock *lock = _locks[idxLock];
        NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[idxBucket];

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

        [self invalidateItemsInDependentGridsWithChange:change];

        [lock unlock];
        [_lockTheTableItself unlockForReading];
    });
}

- (void)willInvalidateItem:(nonnull NSObject <GSGridItem> *)item atPoint:(vector_float3)p
{
    // do nothing
}

- (void)invalidateItemsInDependentGridsWithChange:(nonnull GSGridEdit *)change
{
    assert(change);

    for(GSGrid *grid in _dependentGrids)
    {
        NSSet * (^mapping)(GSGridEdit *) = [_mappingToDependentGrids objectForKey:[grid description]];
        NSSet *correspondingPoints = mapping(change);
        for(GSBoxedVector *q in correspondingPoints)
        {
            GSGridEdit *secondaryChange = [[GSGridEdit alloc] initWithOriginalItem:nil
                                                                        modifiedItem:nil
                                                                                 pos:[q vectorValue]];
            [grid invalidateItemWithChange:secondaryChange];
        }
    }
}

- (void)registerDependentGrid:(GSGrid *)grid mapping:(nonnull NSSet<GSBoxedVector *> * (^)(GSGridEdit *))mapping
{
    [_dependentGrids addObject:grid];
    [_mappingToDependentGrids setObject:[mapping copy] forKey:[grid description]];
}

- (void)replaceItemAtPoint:(vector_float3)p
                 transform:(nonnull NSObject <GSGridItem> * (^)(NSObject <GSGridItem> *original))newReplacementItem
{
    [_lockTheTableItself lockForReading];

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[idxBucket];

    [lock lock];

    // Search for an existing item at the specified point. If it exists then just do a straight-up replacement.
    for(NSUInteger i = 0, n = bucket.count; i < n; ++i)
    {
        NSObject <GSGridItem> *item = [bucket objectAtIndex:i];

        if(vector_equal(item.minP, minP)) {
            NSObject <GSGridItem> *replacement = newReplacementItem(item);
            if([item respondsToSelector:@selector(itemWillBeInvalidated)]) {
                [item itemWillBeInvalidated];
            }
            [bucket replaceObjectAtIndex:i withObject:replacement];
            
            [_lockTheCount lock];
            _costCount -= item.cost;
            _costCount += replacement.cost;
            [_lockTheCount unlock];

            GSGridEdit *change = [[GSGridEdit alloc] initWithOriginalItem:item
                                                           modifiedItem:replacement
                                                                    pos:p];

            [self invalidateItemsInDependentGridsWithChange:change];

            [lock unlock];
            [_lockTheTableItself unlockForReading];
            return;
        }
    }

    // If the item does not already exist in the cache then have the factory retrieve/create it, transform, and add to
    // the cache.
    {
        NSObject <GSGridItem> *replacement = newReplacementItem(_factory(minP));

        [bucket addObject:replacement];

        [_lockTheCount lock];
        _costCount += replacement.cost;
        _count++;
        float load = (float)_count / _numBuckets;
        [_lockTheCount unlock];

        [lock unlock];
        [_lockTheTableItself unlockForReading];

        if(load > _loadLevelToTriggerResize) {
            [self resizeTable];
        }
    }
}

@end