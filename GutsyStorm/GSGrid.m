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
#import "GSActivity.h"
#import "GSGridEdit.h"
#import "GSGridBucket.h"


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSGrid
{
    GSReaderWriterLock *_lockBuckets; // Lock protects _buckets, but not bucket contents.
    NSMutableArray<GSGridBucket *> *_buckets;

    NSLock *_lockTheCount; // Lock protects _count, _costTotal, _lru, and other ivars associated with table limits.
    NSInteger _count;
    float _loadLevelToTriggerResize;
    NSInteger _costTotal;
    NSInteger _costLimit;
    GSGridItemLRU<NSObject <GSGridItem> *> *_lru;

    // Keep a reference to a block which can make new grid items on demand.
    GSGridItemFactory _factory;
}

+ (NSMutableArray<GSGridBucket *> *)newBuckets:(NSUInteger)capacity gridName:(nonnull NSString *)gridName
{
    NSMutableArray<GSGridBucket *> *buckets = [[NSMutableArray alloc] initWithCapacity:capacity];

    if (!buckets) {
        [NSException raise:NSMallocException format:@"Out of memory allocating `_buckets'."];
    }

    for(NSUInteger i=0; i<capacity; ++i)
    {
        NSString *name = [NSString stringWithFormat:@"%@.bucket[%lu]", gridName, (unsigned long)i];
        buckets[i] = [[GSGridBucket alloc] initWithName:name];
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
        _buckets = [[self class] newBuckets:128 gridName:name];
        _lru = [GSGridItemLRU new];
        _name = name;

        _lockTheCount = [NSLock new];
        _lockTheCount.name = [NSString stringWithFormat:@"%@.lockTheCount", name];
        _count = 0;
        _costLimit = 0;
        _loadLevelToTriggerResize = 0.5;

        _lockBuckets = [GSReaderWriterLock new];
        _lockBuckets.name = [NSString stringWithFormat:@"%@.lockBucketsArray", name];
    }

    return self;
}

- (void)resizeTableIfNecessary
{
    dispatch_block_t resizeBlock = ^{
        [_lockBuckets lockForWriting];
        [_lockTheCount lock]; // We don't expect other threads to be here, but take the lock anyway.
        
        // Test again whether a resize is necessary. It's possible, for example, that someone evicted all items just now.
        if(((float)_count / _buckets.count) > _loadLevelToTriggerResize) {
            NSUInteger oldNumBuckets = _buckets.count;
            NSUInteger newNumBuckets = 2 * _buckets.count;
            
            DEBUG_LOG(@"Resizing table \"%@\": buckets %lu -> %lu ; count=%lu",
                      self.name, oldNumBuckets, _numBuckets, _count);
            
            NSMutableArray<GSGridBucket *> *oldBuckets = _buckets;
            
            // Allocate a new, and larger, set of buckets.
            _buckets = [[self class] newBuckets:newNumBuckets gridName:self.name];
            
            // Insert each object into the new hash table.
            for(NSUInteger i=0; i<oldNumBuckets; ++i)
            {
                [oldBuckets[i].lock lock];
            }
            for(NSUInteger i=0; i<oldNumBuckets; ++i)
            {
                for(NSObject <GSGridItem> *item in oldBuckets[i].items)
                {
                    NSUInteger hash = vector_hash(item.minP);
                    [_buckets[hash % newNumBuckets].items addObject:item];
                }
            }
            for(NSUInteger i=0; i<oldNumBuckets; ++i)
            {
                [oldBuckets[i].lock unlock];
            }
        }
        
        [_lockTheCount unlock];
        [_lockBuckets unlockForWriting];
    };

    // Perform a quick test to detect whether a resize is likely necessary.
    // Do not take the write lock unless we think there's a good chance we'll need to resize.
    [_lockBuckets lockForReading];
    [_lockTheCount lock];
    BOOL resizeIsNeeded = ((float)_count / _buckets.count) > _loadLevelToTriggerResize;
    if(resizeIsNeeded) {
        dispatch_async(dispatch_get_global_queue(0, 0), resizeBlock);
    }
    [_lockTheCount unlock];
    [_lockBuckets unlockForReading];
}

- (BOOL)objectAtPoint:(vector_float3)p
             blocking:(BOOL)blocking
               object:(id _Nonnull * _Nullable)item
      createIfMissing:(BOOL)createIfMissing
{
    if(blocking) {
        [_lockBuckets lockForReading];
    } else if(![_lockBuckets tryLockForReading]) {
        return NO;
    }
    
    BOOL result = NO;
    BOOL createdAnItem = NO;
    NSObject <GSGridItem> * anObject = nil;
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _buckets.count;
    GSGridBucket *bucket = _buckets[idxBucket];
    
    if(blocking) {
        [bucket.lock lock];
    } else if(![bucket.lock tryLock]) {
        [_lockBuckets unlockForReading];
        return NO;
    }
    
    anObject = [self _searchForItemAtPosition:minP bucket:bucket];

    if(!anObject && createIfMissing) {
        GSStopwatchTraceStep(@"%@: calling factory", self.name);
        anObject = _factory(minP);
        GSStopwatchTraceStep(@"%@: factory finished", self.name);
        
        if (!anObject) {
            [NSException raise:NSMallocException format:@"Out of memory allocating `anObject' for GSGrid."];
        }

        [_lockTheCount lock];
        [bucket.items addObject:anObject];
        [_lru referenceObject:anObject bucket:bucket];
        _count++;
        _costTotal += anObject.cost;
        [_lockTheCount unlock];

        createdAnItem = YES;
    }
    
    if(anObject) {
        result = YES;
    }
    
    [bucket.lock unlock];
    [_lockBuckets unlockForReading];

    if (createdAnItem) {
        [self _enforceGridCostLimits];
        [self resizeTableIfNecessary];
    }
    
    if (result) {
        if (item) {
            *item = anObject;
        }
    }

    return result;
}

- (nonnull id)objectAtPoint:(vector_float3)p
{
    id anItem = nil;

    [self objectAtPoint:p
               blocking:YES
                 object:&anItem
        createIfMissing:YES];

    if (!anItem) {
        [NSException raise:NSGenericException format:@"Failed to get the object, and failure is not an option."];
    }

    return anItem;
}

- (void)evictItemAtPoint:(vector_float3)p
{
    [_lockBuckets lockForReading];

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _buckets.count;
    GSGridBucket *bucket = _buckets[idxBucket];

    [bucket.lock lock];

    NSObject <GSGridItem> *foundItem = [self _searchForItemAtPosition:minP bucket:bucket];

    if(foundItem) {
        [self _unlockedEvictItem:foundItem bucket:bucket];
    }

    [bucket.lock unlock];
    [_lockBuckets unlockForReading];
}

- (void)evictAllItems
{
    [_lockBuckets lockForWriting]; // Take the global lock to prevent reading from any stripe.
    [self _unlockedEvictAllItems];
    [_lockBuckets unlockForWriting];
}

- (void)invalidateItemAtPoint:(vector_float3)pos
{
    [_lockBuckets lockForReading];
    
    vector_float3 minP = GSMinCornerForChunkAtPoint(pos);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _buckets.count;
    GSGridBucket *bucket = _buckets[idxBucket];
    
    [bucket.lock lock];
    
    NSObject <GSGridItem> *foundItem = [self _searchForItemAtPosition:minP bucket:bucket];
    
    if(foundItem) {
        [self willInvalidateItemAtPoint:foundItem.minP];

        [_lockTheCount lock];
        _count--;
        _costTotal -= foundItem.cost;
        [bucket.items removeObject:foundItem];
        [_lru removeObject:foundItem];
        [_lockTheCount unlock];
    }
    
    [bucket.lock unlock];
    [_lockBuckets unlockForReading];
}

- (void)willInvalidateItemAtPoint:(vector_float3)p
{
    // do nothing
}

- (nonnull GSGridEdit *)replaceItemAtPoint:(vector_float3)p transform:(nonnull GSGridTransform)newReplacementItem
{
    GSGridEdit *change = nil;

    NSParameterAssert(newReplacementItem);

    [_lockBuckets lockForReading];

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _buckets.count;
    GSGridBucket *bucket = _buckets[idxBucket];
    NSUInteger indexOfFoundItem = NSNotFound;

    [bucket.lock lock];

    // Search for an existing item at the specified point. If it exists then just do a straight-up replacement.
    for(NSUInteger i = 0, n = bucket.items.count; i < n; ++i)
    {
        NSObject <GSGridItem> *item = [bucket.items objectAtIndex:i];

        if(vector_equal(item.minP, minP)) {
            indexOfFoundItem = i;
            break;
        }
    }
    
    // If the item does not already exist in the cache then have the factory retrieve/create it, transform, and add to
    // the cache.
    if (indexOfFoundItem == NSNotFound) {
        NSObject <GSGridItem> *item = newReplacementItem(_factory(minP));
        change = [[GSGridEdit alloc] initWithOriginalItem:nil modifiedItem:item pos:p];
        [_lockTheCount lock];
        [bucket.items addObject:item];
        [_lru referenceObject:item bucket:bucket];
        _costTotal += item.cost;
        _count++;
        [_lockTheCount unlock];
    } else {
        NSObject <GSGridItem> *item = [bucket.items objectAtIndex:indexOfFoundItem];
        NSObject <GSGridItem> *replacement = newReplacementItem(item);
        change = [[GSGridEdit alloc] initWithOriginalItem:item modifiedItem:replacement pos:p];
        [self _unlockedReplaceItemAtIndex:indexOfFoundItem inBucket:bucket withChange:change];
    }

    [bucket.lock unlock];
    [_lockBuckets unlockForReading];

    [self _enforceGridCostLimits];

    if (indexOfFoundItem == NSNotFound) {
        [self resizeTableIfNecessary];
    }
    
    return change;
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

- (void)_unlockedEvictItem:(nonnull NSObject <GSGridItem> *)item bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(item);
    NSParameterAssert(bucket);
    
    [_lockTheCount lock];
    _count--;
    _costTotal -= item.cost;
    
    [bucket.items removeObject:item];
    [_lru removeObject:item];
    [_lockTheCount unlock];
}

- (void)_unlockedEvictAllItems
{
    for(NSUInteger i=0, n=_buckets.count; i<n; ++i)
    {
        GSGridBucket *bucket = _buckets[i];
        [bucket.items removeAllObjects];
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
                           inBucket:(nonnull GSGridBucket *)bucket
                         withChange:(nonnull GSGridEdit *)change
{
    NSParameterAssert(bucket);
    NSParameterAssert(index < bucket.items.count);
    NSParameterAssert(change);
    
    NSObject <GSGridItem> *item = [bucket.items objectAtIndex:index];
    NSAssert(item == change.originalObject, @"`change' is inconsistent");
    
    NSObject <GSGridItem> *replacement = change.modifiedObject;
    NSAssert(replacement, @"`change.modifiedObject' must not be nil");

    [self willInvalidateItemAtPoint:change.pos];

    // We can replace an item without taking the write lock on the whole table. We only need to enter this method
    // while holding the lock on the relevant stripe. Take `_lockTheCount' to ensure consistent updates to the limits.
    // We modify the bucket while holding the lock so that we can be certain that, inside the lock, the grid limits are
    // always consistent. In any case, replacing an item in a bucket like this is fast. So, we expect it to be low cost.
    [_lockTheCount lock];
    [_lru removeObject:item];
    [bucket.items replaceObjectAtIndex:index withObject:replacement];
    [_lru referenceObject:replacement bucket:bucket];
    _costTotal -= item.cost;
    _costTotal += replacement.cost;
    [_lockTheCount unlock];
}

- (nullable NSObject <GSGridItem> *)_searchForItemAtPosition:(vector_float3)minP
                                                      bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(bucket);
    
    for(NSObject <GSGridItem> *item in bucket.items)
    {
        if(vector_equal(item.minP, minP)) {
            return item;
        }
    }
    
    return nil;
}

- (void)_enforceGridCostLimits
{
    dispatch_block_t enforceLimits = ^{
        [_lockBuckets lockForWriting];
        
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
            
            GSGridBucket *bucket = nil;
            NSObject <GSGridItem> *item = nil;
            [_lru popAndReturnObject:&item bucket:&bucket];
            if (item && bucket) {
                DEBUG_LOG(@"Grid \"%@\" is over budget and will evict %@ cost item",
                          self.name, [self.costFormatter stringForObjectValue:@(item.cost)]);
                [self _unlockedEvictItem:item bucket:bucket];
            }
        }
        
        DEBUG_LOG(@"Grid \"%@\" -- done enforcing grid limits", self.name);
        
        [_lockBuckets unlockForWriting];
    };

    // Perform a quick test to detect the grid is likely over the cost limit.
    // Do not take the write lock unless we think there's a good chance we'll need to evict some items.
    [_lockBuckets lockForReading];
    [_lockTheCount lock];
    BOOL overLimit = (_costLimit > 0) && (_costTotal > _costLimit);
    if (overLimit) {
        dispatch_async(dispatch_get_global_queue(0, 0), enforceLimits);
    }
    [_lockTheCount unlock];
    [_lockBuckets unlockForReading];
}

@end