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
#import "GSGridEdit.h"
#import "GSGridBucket.h"


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSGrid
{
    GSReaderWriterLock *_lockBuckets; // This lock protects _buckets, but not bucket contents.
    NSMutableArray<GSGridBucket *> *_buckets;

    NSLock *_lockTheCount; // This lock protects _count and _loadLevelToTriggerResize.
    NSInteger _count;
    float _loadLevelToTriggerResize;
    
    // XXX: The cost limits have been temporarily removed. They need tp be reimplemented for the world with slots.
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
        _loadLevelToTriggerResize = 0.5;

        _lockBuckets = [GSReaderWriterLock new];
        _lockBuckets.name = [NSString stringWithFormat:@"%@.lockBucketsArray", name];
        _buckets = [[self class] newBuckets:128 gridName:name];
    }

    return self;
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
        _count++;
        [self _unlockedResizeTableIfNecessary];
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
    [_lockBuckets lockForReading];

    for(NSUInteger i=0, n=_buckets.count; i<n; ++i)
    {
        GSGridBucket *bucket = _buckets[i];

        [_lockTheCount lock];

        _count -= bucket.slots.count;

        [bucket.lock lock];
        [bucket.slots removeAllObjects];
        [bucket.lock unlock];
        
        [_lockTheCount unlock];
    }

    [_lockBuckets unlockForReading];
}

- (nonnull NSString *)description
{
    [_lockTheCount lock];
    NSUInteger count = _count;
    [_lockTheCount unlock];

    return [NSString stringWithFormat:@"%@: count=%lu", self.name, count];
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

@end