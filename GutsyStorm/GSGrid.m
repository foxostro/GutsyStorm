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
#import "GSGridLRU.h"
#import "GSActivity.h"
#import "GSGridBucket.h"


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSGrid
{
    GSReaderWriterLock *_lockBuckets; // This lock protects _buckets, but not bucket contents.
    NSMutableArray<GSGridBucket *> *_buckets;

    NSLock *_lockTheCount; // This lock protects _count, _countLimit, _loadLevelToTriggerResize, and _lru.
    NSInteger _count;
    NSInteger _countLimit;
    float _loadLevelToTriggerResize;
    GSGridLRU *_lru;
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
{
    if (self = [super init]) {
        _name = name;

        _lockTheCount = [NSLock new];
        _lockTheCount.name = [NSString stringWithFormat:@"%@.lockTheCount", name];
        _count = 0;
        _countLimit = 0;
        _loadLevelToTriggerResize = 0.5;
        _lru = [GSGridLRU new];

        _lockBuckets = [GSReaderWriterLock new];
        _lockBuckets.name = [NSString stringWithFormat:@"%@.lockBucketsArray", name];
        _buckets = [[self class] newBuckets:128 gridName:name];
    }

    return self;
}

- (nullable GSGridSlot *)slotAtPoint:(vector_float3)p blocking:(BOOL)blocking
{
    if(blocking) {
        [_lockBuckets lockForReading];
    } else if(![_lockBuckets tryLockForReading]) {
        return nil;
    }

    GSGridSlot *slot = nil;
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSUInteger hash = vector_hash(minP);
    NSUInteger idxBucket = hash % _buckets.count;
    GSGridBucket *bucket = _buckets[idxBucket];
    
    if(blocking) {
        [bucket.lock lock];
    } else if(![bucket.lock tryLock]) {
        [_lockBuckets unlockForReading];
        return nil;
    }
    
    slot = [self _searchForSlotAtPosition:minP bucket:bucket];

    if(!slot) {
        slot = [[GSGridSlot alloc] initWithMinP:minP];
        
        if (!slot) {
            [NSException raise:NSMallocException format:@"Out of memory allocating `anObject' for GSGrid."];
        }

        [_lockTheCount lock];
        [bucket.slots addObject:slot];
        [_lru referenceObject:[GSBoxedVector boxedVectorWithVector:minP] bucket:bucket];
        _count++;
        [self _unlockedResizeTableIfNecessary];
        [self _unlockedEnforceGridLimitsIfNecessary];
        [_lockTheCount unlock];
    }
    
    [bucket.lock unlock];
    [_lockBuckets unlockForReading];
    
    return slot;
}

- (nonnull GSGridSlot *)slotAtPoint:(vector_float3)p
{
    GSGridSlot *slot = [self slotAtPoint:p blocking:YES];

    if (!slot) {
        [NSException raise:NSGenericException format:@"Failed to get the object, and failure is not an option."];
    }

    return slot;
}

- (void)evictAllItems
{
    [_lockBuckets lockForWriting];
    [_lockTheCount lock];

    for(NSUInteger i=0, n=_buckets.count; i<n; ++i)
    {
        [_buckets[i].lock lock];
    }

    for(NSUInteger i=0, n=_buckets.count; i<n; ++i)
    {
        [_buckets[i].slots removeAllObjects];
    }

    [_lru removeAllObjects];
    _count = 0;

    for(NSUInteger i=0, n=_buckets.count; i<n; ++i)
    {
        [_buckets[i].lock unlock];
    }

    [_lockTheCount unlock];
    [_lockBuckets unlockForWriting];
}

- (nonnull NSString *)description
{
    [_lockTheCount lock];
    NSUInteger count = _count;
    [_lockTheCount unlock];

    return [NSString stringWithFormat:@"%@: count=%lu", self.name, count];
}

- (NSInteger)count
{
    NSInteger c;
    [_lockTheCount lock];
    c = _count;
    [_lockTheCount unlock];
    return c;
}

- (NSInteger)countLimit
{
    NSInteger c;
    [_lockTheCount lock];
    c = _countLimit;
    [_lockTheCount unlock];
    return c;
}

- (void)setCountLimit:(NSInteger)countLimit
{
    [_lockTheCount lock];
    
    if (countLimit != _countLimit) {
        _countLimit = countLimit;
        [self _unlockedEnforceGridLimitsIfNecessary];
    }
    
    [_lockTheCount unlock];
}

#pragma mark Private

- (nullable GSGridSlot *)_searchForSlotAtPosition:(vector_float3)minP bucket:(nonnull GSGridBucket *)bucket
{
    NSParameterAssert(bucket);
    
    for(GSGridSlot *slot in bucket.slots)
    {
        if(vector_equal(slot.minP, minP)) {
            return slot;
        }
    }
    
    return nil;
}

- (void)_unlockedResizeTableIfNecessary
{
    // The locks _lockTheCount and _lockBuckets must be held before entering this method.
    
    dispatch_block_t resizeBlock = ^{
        [_lockBuckets lockForWriting];
        [_lockTheCount lock]; // We don't expect other threads to be here, but take the lock anyway.
        
        // Test again whether a resize is necessary. It's possible, for example, that someone evicted all items just now.
        if(((float)_count / _buckets.count) > _loadLevelToTriggerResize) {
            NSUInteger oldNumBuckets = _buckets.count;
            NSUInteger newNumBuckets = 2 * _buckets.count;
            
            DEBUG_LOG(@"Resizing table \"%@\": buckets %lu -> %lu ; count=%lu",
                      self.name, oldNumBuckets, newNumBuckets, _count);
            
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
                for(GSGridSlot *slot in oldBuckets[i].slots)
                {
                    NSUInteger hash = vector_hash(slot.minP);
                    [_buckets[hash % newNumBuckets].slots addObject:slot];
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
    
    BOOL resizeIsNeeded = ((float)_count / _buckets.count) > _loadLevelToTriggerResize;
    if(resizeIsNeeded) {
        dispatch_async(dispatch_get_global_queue(0, 0), resizeBlock);
    }
}

- (void)_unlockedEnforceGridLimitsIfNecessary
{
    // The lock `_lockTheCount' must be held before entering this method.

    dispatch_block_t enforceLimits = ^{
        [_lockBuckets lockForWriting];
        [_lockTheCount lock];
        
        DEBUG_LOG(@"Grid \"%@\" -- enforcing grid limits", self.name);
        
        if (_countLimit > 0) while(_count > _countLimit)
        {
            GSGridBucket *bucket = nil;
            GSBoxedVector *position = nil;
            [_lru popAndReturnObject:&position bucket:&bucket];
            assert(position && bucket);

            vector_float3 minP = [position vectorValue];
            NSUInteger index = [bucket.slots indexOfObjectPassingTest:^BOOL(GSGridSlot * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                return vector_equal(obj.minP, minP);
            }];
            assert(index >= 0);

            DEBUG_LOG(@"Grid \"%@\" is over budget and will evict slot now.", self.name);

            _count--;
            [bucket.slots removeObjectAtIndex:index];
        }
        
        DEBUG_LOG(@"Grid \"%@\" -- done enforcing grid limits", self.name);
        
        [_lockTheCount unlock];
        [_lockBuckets unlockForWriting];
    };

    // Perform a quick test to detect the grid is likely over the cost limit.
    // Do not take the write lock unless we think there's a good chance we'll need to evict some items.
    if (_countLimit > 0 && _count > _countLimit) {
        dispatch_async(dispatch_get_global_queue(0, 0), enforceLimits);
    }
}

@end