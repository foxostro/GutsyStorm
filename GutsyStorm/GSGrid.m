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
#import "GSGridItemLRU.h"


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSGrid
{
    GSReaderWriterLock *_lockTheTableItself; // Lock protects _buckets and _numBuckets, but not bucket contents.
    NSUInteger _numBuckets;
    NSMutableArray<NSObject <GSGridItem> *> * __strong *_buckets;

    // These locks are used for lock striping across the buckets. These protect bucket contents.
    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    NSLock *_lockTheCount; // Lock protects _count, _costTotal, _lru, and other ivars associated with table limits.
    NSInteger _count;
    float _loadLevelToTriggerResize;
    NSInteger _costTotal;
    NSInteger _costLimit;
    GSGridItemLRU *_lru;

    // Keep a reference to a block which can make new grid items on demand.
    GSGridItemFactory _factory;

    // The grid maintains relationships with other grids. Invalidating an item in this grid may invalidate items in
    // the associated grids as well.
    NSMutableArray<GSGrid *> *_dependentGrids;
    NSMutableDictionary *_mappingToDependentGrids;
}

+ (NSMutableArray<NSObject <GSGridItem> *> * __strong *)newBuckets:(NSUInteger)count
{
    NSMutableArray<NSObject <GSGridItem> *> * __strong *buckets = (NSMutableArray<NSObject <GSGridItem> *> * __strong *)calloc(count, sizeof(NSMutableArray<NSObject <GSGridItem> *> *));
    
    if (!buckets) {
        [NSException raise:NSMallocException format:@"Out of memory allocating `_buckets'."];
    }
    
    for(NSUInteger i=0; i<count; ++i)
    {
        buckets[i] = [NSMutableArray<NSObject <GSGridItem> *> new];
    }
    
    return buckets;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                             factory:(nonnull GSGridItemFactory)factory
{
    if (self = [super init]) {
        _factory = [factory copy];
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 2;
        _numBuckets = 1024;
        _buckets = [[self class] newBuckets:_numBuckets];
        _lru = [GSGridItemLRU new];
        _dependentGrids = [NSMutableArray<GSGrid *> new];
        _mappingToDependentGrids = [NSMutableDictionary new];
        _name = name;

        _lockTheCount = [NSLock new];
        _lockTheCount.name = [NSString stringWithFormat:@"%@.lockTheCount", name];
        _count = 0;
        _costLimit = 0;
        _loadLevelToTriggerResize = 0.80;

        _locks = (NSLock * __strong *)calloc(_numLocks, sizeof(NSLock *));
        if (!_locks) {
            [NSException raise:NSMallocException format:@"Out of memory allocating `_locks'."];
        }
        for(NSUInteger i=0; i<_numLocks; ++i)
        {
            _locks[i] = [NSLock new];
            _locks[i].name = [NSString stringWithFormat:@"%@.lock[%lu]", name, i];
        }

        _lockTheTableItself = [GSReaderWriterLock new];
        _lockTheTableItself.name = [NSString stringWithFormat:@"%@.lockTheTableItself", name];
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

- (void)resizeTableIfNecessary
{
    // Perform a quick test to detect whether a resize is likely necessary.
    // Do not take the write lock unless we think there's a good chance we'll need to resize.
    [_lockTheTableItself lockForReading];
    [_lockTheCount lock];
    NSAssert(_numBuckets>0, @"Cannot have zero buckets.");
    BOOL resizeIsNeeded = ((float)_count / _numBuckets) > _loadLevelToTriggerResize;
    [_lockTheCount unlock];
    [_lockTheTableItself unlockForReading];

    if(!resizeIsNeeded) {
        return;
    }

    [_lockTheTableItself lockForWriting];
    [_lockTheCount lock]; // We don't expect other threads to be here, but take the lock anyway.

    // Test again whether a resize is necessary. It's possible, for example, that someone evicted all items just now.
    NSAssert(_numBuckets>0, @"Cannot have zero buckets.");
    if(((float)_count / _numBuckets) > _loadLevelToTriggerResize) {
        NSUInteger oldNumBuckets = _numBuckets;

        _numBuckets *= 2;
        DEBUG_LOG(@"Resizing table \"%@\": buckets %lu -> %lu ; count=%lu",
                  self.name, oldNumBuckets, _numBuckets, _count);

        NSMutableArray<NSObject <GSGridItem> *> * __strong *oldBuckets = _buckets;

        // Allocate a new, and larger, set of buckets.
        _buckets = [[self class] newBuckets:_numBuckets];

        // Insert each object into the new hash table.
        for(NSUInteger i=0; i<oldNumBuckets; ++i)
        {
            for(NSObject <GSGridItem> *item in oldBuckets[i])
            {
                NSUInteger hash = vector_hash(item.minP);
                [_buckets[hash % _numBuckets] addObject:item];
            }
        }
        
        // Free the old set of buckets.
        for(NSUInteger i=0; i<oldNumBuckets; ++i)
        {
            oldBuckets[i] = nil;
        }
        free(oldBuckets);
    }
    
    [_lockTheCount unlock];
    [_lockTheTableItself unlockForWriting];
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
    
    anObject = [self _searchForItemAtPosition:minP bucket:bucket];
    
    if(!anObject && createIfMissing) {
        anObject = _factory(minP);
        
        if (!anObject) {
            factoryDidFail = YES;
            
            if (GSGridItemFactoryFailureResponse_Abort == self.factoryFailureResponse) {
                [NSException raise:NSMallocException format:@"Out of memory allocating `anObject' for GSGrid."];
            }
        } else {
            [_lockTheCount lock];
            [bucket addObject:anObject];
            [_lru referenceObject:anObject bucket:bucket];
            _count++;
            _costTotal += anObject.cost;
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
        [self _enforceGridCostLimits];
        [self resizeTableIfNecessary];
        
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

    if (!anItem) {
        [NSException raise:NSGenericException format:@"Failed to get the object, and failure is not an option."];
    }

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

    NSObject <GSGridItem> *foundItem = [self _searchForItemAtPosition:minP bucket:bucket];

    if(foundItem) {
        [self _unlockedEvictItem:foundItem bucket:bucket];
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];
}

- (void)evictAllItems
{
    [_lockTheTableItself lockForWriting]; // Take the global lock to prevent reading from any stripe.
    [self _unlockedEvictAllItems];
    [_lockTheTableItself unlockForWriting];
}

- (void)invalidateItemWithChange:(nonnull GSGridEdit *)change
{
    NSParameterAssert(change);

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

        NSObject <GSGridItem> *foundItem = [self _searchForItemAtPosition:minP bucket:bucket];

        if(foundItem) {
            [self _unlockedInvalidateItem:foundItem bucket:bucket change:change];
        }

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
        NSSet * (^mapping)(GSGridEdit *) = [_mappingToDependentGrids objectForKey:[grid _key]];
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
    NSParameterAssert(grid);
    NSParameterAssert(mapping);
    [_dependentGrids addObject:grid];
    [_mappingToDependentGrids setObject:[mapping copy] forKey:[grid _key]];
}

- (void)replaceItemAtPoint:(vector_float3)p
                 transform:(nonnull NSObject <GSGridItem> * (^)(NSObject <GSGridItem> *original))newReplacementItem
{
    NSParameterAssert(newReplacementItem);

    [_lockTheTableItself lockForReading];

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[idxBucket];
    NSUInteger indexOfFoundItem = NSNotFound;

    [lock lock];

    // Search for an existing item at the specified point. If it exists then just do a straight-up replacement.
    for(NSUInteger i = 0, n = bucket.count; i < n; ++i)
    {
        NSObject <GSGridItem> *item = [bucket objectAtIndex:i];

        if(vector_equal(item.minP, minP)) {
            indexOfFoundItem = i;
            break;
        }
    }
    
    // If the item does not already exist in the cache then have the factory retrieve/create it, transform, and add to
    // the cache.
    if (indexOfFoundItem == NSNotFound) {
        NSObject <GSGridItem> *item = newReplacementItem(_factory(minP));
        [_lockTheCount lock];
        [bucket addObject:item];
        [_lru referenceObject:item bucket:bucket];
        _costTotal += item.cost;
        _count++;
        [_lockTheCount unlock];
    } else {
        NSObject <GSGridItem> *item = [bucket objectAtIndex:indexOfFoundItem];
        NSObject <GSGridItem> *replacement = newReplacementItem(item);

        GSGridEdit *change = [[GSGridEdit alloc] initWithOriginalItem:item
                                                         modifiedItem:replacement
                                                                  pos:p];
        
        [self _unlockedReplaceItemAtIndex:indexOfFoundItem inBucket:bucket withChange:change];
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    [self _enforceGridCostLimits];

    if (indexOfFoundItem == NSNotFound) {
        [self resizeTableIfNecessary];
    }
}

- (void)setCostLimit:(NSInteger)costLimit
{
    BOOL didChangeCostLimit = NO;

    [_lockTheCount lock];
    if (_costLimit != costLimit) {
        _costLimit = costLimit;
        didChangeCostLimit = YES;
    }
    [_lockTheCount unlock];
    
    if (didChangeCostLimit) {
        [self _enforceGridCostLimits];
    }
}

- (void)capCosts
{
    BOOL didChangeCostLimit = NO;
    
    [_lockTheCount lock];
    if (_costLimit != _costTotal) {
        _costLimit = _costTotal;
        didChangeCostLimit = YES;
    }
    [_lockTheCount unlock];
    
    if (didChangeCostLimit) {
        [self _enforceGridCostLimits];
    }
}

- (nonnull NSString *)description
{
    [_lockTheCount lock];
    NSUInteger costTotal = _costTotal;
    NSUInteger costLimit = _costLimit;
    NSUInteger count = _count;
    [_lockTheCount unlock];
    
    NSFormatter *formatter = self.costFormatter;
    NSString *strCostTotal;
    NSString *strCostLimit;

    if (formatter) {
        strCostTotal = [formatter stringForObjectValue:@(costTotal)];
        strCostLimit = [formatter stringForObjectValue:@(costLimit)];
    } else {
        strCostTotal = [NSString stringWithFormat:@"%lu", costTotal];
        strCostLimit = [NSString stringWithFormat:@"%lu", costLimit];
    }

    return [NSString stringWithFormat:@"%@: costTotal=%@, costLimit=%@, count=%lu",
            self.name, strCostTotal, strCostLimit, count];
}

#pragma mark Private

- (nonnull NSString *)_key
{
    return [super description];
}

- (void)_unlockedEvictItem:(nonnull NSObject <GSGridItem> *)item
                    bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket
{
    NSParameterAssert(item);
    NSParameterAssert(bucket);
    
    [_lockTheCount lock];
    _count--;
    _costTotal -= item.cost;
    
    if([item respondsToSelector:@selector(itemWillBeEvicted)]) {
        [item itemWillBeEvicted];
    }
    
    [bucket removeObject:item];
    [_lru removeObject:item];
    [_lockTheCount unlock];
}

- (void)_unlockedInvalidateItem:(nonnull NSObject <GSGridItem> *)item
                         bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket
                         change:(nonnull GSGridEdit *)change
{
    NSParameterAssert(item);
    NSParameterAssert(bucket);
    NSParameterAssert(change);
    
    if([item respondsToSelector:@selector(itemWillBeInvalidated)]) {
        [item itemWillBeInvalidated];
    }
    
    [self willInvalidateItem:item atPoint:change.pos];
    
    if(item) {
        [_lockTheCount lock];
        _count--;
        _costTotal -= item.cost;
        [bucket removeObject:item];
        [_lru removeObject:item];
        [_lockTheCount unlock];
    }
    
    [self invalidateItemsInDependentGridsWithChange:change];
}

- (void)_unlockedEvictAllItems
{
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[i];
        
        for(NSObject <GSGridItem> *item in bucket)
        {
            if([item respondsToSelector:@selector(itemWillBeEvicted)]) {
                [item itemWillBeEvicted];
            }
        }
    }
    
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        NSMutableArray<NSObject <GSGridItem> *> *bucket = _buckets[i];
        [bucket removeAllObjects];
    }
    
    // We don't expect there to be any other threads here right now because we took the grid's write lock before
    // entering this method. Still, take the lock to be sure. (It's cheap since there's no contention.)
    [_lockTheCount lock];
    _count = 0;
    _costTotal = 0;
    [_lru removeAllObjects];
    [_lockTheCount unlock];
}

- (void)_unlockedReplaceItemAtIndex:(NSUInteger)index
                           inBucket:(nonnull NSMutableArray *)bucket
                         withChange:(nonnull GSGridEdit *)change
{
    NSParameterAssert(bucket);
    NSParameterAssert(index < bucket.count);
    NSParameterAssert(change);
    
    NSObject <GSGridItem> *item = [bucket objectAtIndex:index];
    NSAssert(item == change.originalObject, @"`change' is inconsistent");
    
    NSObject <GSGridItem> *replacement = change.modifiedObject;
    NSAssert(replacement, @"`change.modifiedObject' must not be nil");

    if([item respondsToSelector:@selector(itemWillBeInvalidated)]) {
        [item itemWillBeInvalidated];
    }

    // We can replace an item without taking the write lock on the whole table. We only need to enter this method
    // while holding the lock on the relevant stripe. Take `_lockTheCount' to ensure consistent updates to the limits.
    // We modify the bucket while holding the lock so that we can be certain that, inside the lock, the grid limits are
    // always consistent. In any case, replacing an item in a bucket like this is fast. So, we expect it to be low cost.
    [_lockTheCount lock];
    [_lru referenceObject:item bucket:bucket];
    [_lru removeObject:replacement];
    [bucket replaceObjectAtIndex:index withObject:replacement];
    _costTotal -= item.cost;
    _costTotal += replacement.cost;
    [_lockTheCount unlock];

    [self invalidateItemsInDependentGridsWithChange:change];
}

- (nullable NSObject <GSGridItem> *)_searchForItemAtPosition:(vector_float3)minP
                                                      bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket
{
    NSParameterAssert(bucket);
    
    for(NSObject <GSGridItem> *item in bucket)
    {
        if(vector_equal(item.minP, minP)) {
            return item;
        }
    }
    
    return nil;
}

- (void)_enforceGridCostLimits
{
    // Perform a quick test to detect the grid is likely over the cost limit.
    // Do not take the write lock unless we think there's a good chance we'll need to evict some items.
    [_lockTheTableItself lockForReading];
    [_lockTheCount lock];
    BOOL overLimit = (_costLimit > 0) && (_costTotal > _costLimit);
    [_lockTheCount unlock];
    [_lockTheTableItself unlockForReading];

    if(!overLimit) {
        return;
    }

    [_lockTheTableItself lockForWriting];
    
    DEBUG_LOG(@"Grid \"%@\" -- enforcing grid limits", self.name);

    while(true)
    {
        // Test again whether the grid is over the cost limit.
        // It's possible, for example, that someone evicted all items just now.
        [_lockTheCount lock];
        BOOL acceptableGridCost = (_costLimit <= 0) || (_costTotal <= _costLimit);
        [_lockTheCount unlock];

        if (acceptableGridCost) {
            break;
        }

        NSMutableArray<NSObject <GSGridItem> *> *bucket = nil;
        NSObject <GSGridItem> *item = nil;
        [_lru popAndReturnObject:&item bucket:&bucket];
        if (item && bucket) {
            DEBUG_LOG(@"Grid \"%@\" is over budget and will evict %@ cost item",
                      self.name, [self.costFormatter stringForObjectValue:@(item.cost)]);
            [self _unlockedEvictItem:item bucket:bucket];
        }
    }
    
    DEBUG_LOG(@"Grid \"%@\" -- done enforcing grid limits", self.name);

    [_lockTheTableItself unlockForWriting];
}

@end