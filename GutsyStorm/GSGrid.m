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


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSGrid
{
    GSReaderWriterLock *_lockTheTableItself; // Lock protects the "buckets" array itself, but not its contents.

    NSUInteger _numBuckets;
    NSMutableArray<NSObject <GSGridItem> *> * __strong *_buckets;

    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    NSLock *_lockTheCount;
    NSInteger _count;
    float _loadLevelToTriggerResize;
    NSInteger _costCount;
    NSInteger _costLimit;
    
    GSGridItemFactory _factory;

    NSMutableArray<GSGrid *> *_dependentGrids;
    NSMutableDictionary *_mappingToDependentGrids;
}

- (nonnull instancetype)init
{
    assert(!"call -initWithFactory: instead");
    @throw nil;
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

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                             factory:(nonnull GSGridItemFactory)factory
{
    if (self = [super init]) {
        _factory = [factory copy];
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 2;
        _numBuckets = 2;
        _buckets = [[self class] newBuckets:_numBuckets];
        _dependentGrids = [NSMutableArray<GSGrid *> new];
        _mappingToDependentGrids = [NSMutableDictionary new];
        _name = name;

        _lockTheCount = [NSLock new];
        _lockTheCount.name = [NSString stringWithFormat:@"%@.lockTheCount", name];
        _count = 0;
        _costLimit = 0; // XXX: need to allow this to be specified
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
    [_lockTheCount lock]; // Not strictly necessary since locking the table prevents reading too.

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
            
            if (!self.factoryMayFail) {
                [NSException raise:NSMallocException format:@"Out of memory allocating `anObject' for GSGrid."];
            }
        } else {
            [_lockTheCount lock];
            [bucket addObject:anObject];
            _count++;
            _costCount += anObject.cost;
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
        // AFOX_TODO: This would be a great time to enforce grid cost limits.
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
    NSParameterAssert(grid);
    NSParameterAssert(mapping);
    [_dependentGrids addObject:grid];
    [_mappingToDependentGrids setObject:[mapping copy] forKey:[grid description]];
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
        _costCount += item.cost;
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
    
    // AFOX_TODO: This would be a great time to enforce grid cost limits.
    
    if (indexOfFoundItem == NSNotFound) {
        [self resizeTableIfNecessary];
    }
}

#pragma mark Private

- (void)_unlockedEvictItem:(nonnull NSObject <GSGridItem> *)item
                    bucket:(nonnull NSMutableArray<NSObject <GSGridItem> *> *)bucket
{
    NSParameterAssert(item);
    NSParameterAssert(bucket);
    
    [_lockTheCount lock];
    _count--;
    _costCount -= item.cost;
    
    if([item respondsToSelector:@selector(itemWillBeEvicted)]) {
        [item itemWillBeEvicted];
    }
    
    [bucket removeObject:item];
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
        _costCount -= item.cost;
        [bucket removeObject:item];
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
    
    [_lockTheCount lock];
    _count = 0;
    _costCount = 0;
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
    [bucket replaceObjectAtIndex:index withObject:change.modifiedObject];

    [_lockTheCount lock];
    _costCount -= item.cost;
    _costCount += replacement.cost;
    [_lockTheCount unlock];

    [self invalidateItemsInDependentGridsWithChange:change];

    // AFOX_TODO: This would be a great time to enforce grid cost limits.
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

@end