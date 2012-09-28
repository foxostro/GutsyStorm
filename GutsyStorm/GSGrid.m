//
//  GSGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/23/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSGrid.h"
#import "GSChunkData.h"

@implementation GSGrid

- (id)init
{
    return [self initWithActiveRegionArea:1024];
}

- (id)initWithActiveRegionArea:(size_t)areaXZ
{
    self = [super init];
    if (self) {
        numLocks = [[NSProcessInfo processInfo] processorCount] * 64;
        numBuckets = MAX(areaXZ, numLocks);
        n = 0;
        loadLevelToTriggerResize = 0.80;
        
        buckets = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            buckets[i] = [[NSMutableArray alloc] init];
        }
        
        locks = malloc(numLocks * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numLocks; ++i)
        {
            locks[i] = [[NSLock alloc] init];
        }
        
        lockTheTableItself = [[GSReaderWriterLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    for(NSUInteger i=0; i<numBuckets; ++i)
    {
        [buckets[i] release];
    }
    free(buckets);
    
    for(NSUInteger i=0; i<numLocks; ++i)
    {
        [locks[i] release];
    }
    free(locks);
    
    [lockTheTableItself release];
    
    [super dealloc];
}

- (void)resizeTable
{
    [lockTheTableItself lockForWriting];
    
    n = 0;
    
    NSUInteger oldNumBuckets = numBuckets;
    NSMutableArray **oldBuckets = buckets;
    
    // Allocate memory for a new set of buckets.
    numBuckets *= 2;
    buckets = malloc(numBuckets * sizeof(NSMutableArray *));
    for(NSUInteger i=0; i<numBuckets; ++i)
    {
        buckets[i] = [[NSMutableArray alloc] init];
    }
    
    // Insert each object into the new hash table.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        for(GSChunkData *item in oldBuckets[i])
        {
            NSUInteger hash = GSVector3_Hash(item.minP);
            [buckets[hash % numBuckets] addObject:item];
            n++;
        }
    }
    
    // Free the old set of buckets.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        [oldBuckets[i] release];
    }
    free(oldBuckets);
    
    [lockTheTableItself unlockForWriting];
}

- (id)objectAtPoint:(GSVector3)p objectFactory:(id (^)(GSVector3 minP))factory
{
    [lockTheTableItself lockForReading]; // The only writer is -resizeTable, so lock contention will be extremely low.
    
    float load = 0;
    id anObject = nil;
    GSVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    NSUInteger hash = GSVector3_Hash(minP);
    NSUInteger idxBucket = hash % numBuckets;
    NSUInteger idxLock = hash % numLocks;
    NSLock *lock = locks[idxLock];
    NSMutableArray *bucket = buckets[idxBucket];
    
    [lock lock];
    
    for(GSChunkData *item in bucket)
    {
        if(GSVector3_AreEqual(item.minP, minP)) {
            anObject = item;
        }
    }
    
    if(!anObject) {
        anObject = factory(minP);
        assert(anObject);
        [bucket addObject:anObject];
        OSAtomicIncrement32Barrier(&n);
        load = (float)n / numBuckets;
    }
    
    [lock unlock];
    [lockTheTableItself unlockForReading];
    
    if(load > loadLevelToTriggerResize) {
        [self resizeTable];
    }
    
    return anObject;
}

@end
