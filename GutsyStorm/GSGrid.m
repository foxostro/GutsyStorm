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
        // TODO: table should rehash when load exceeds 80%.
        // Choosing this number of buckets generally gives a hash table load of ~30% on game launch.
        numBuckets = areaXZ << 4;
        
        // Choosing this number of locks gives ~2% time spent blocked on hash table locks during game launch.
        numLocks = [[NSProcessInfo processInfo] processorCount] * 64;
        
        buckets = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            buckets[i] = [[NSMutableArray alloc] init];
        }
        
        locks = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numLocks; ++i)
        {
            locks[i] = [[NSLock alloc] init];
        }
        
        n = 0;
    }
    
    return self;
}

- (void)dealloc
{
    for(NSUInteger i=0; i<numBuckets; ++i)
    {
        [buckets[i] release];
    }
    
    for(NSUInteger i=0; i<numLocks; ++i)
    {
        [locks[i] release];
    }
    
    free(buckets);
    free(locks);
    [super dealloc];
}

- (id)objectAtPoint:(GSVector3)p objectFactory:(id (^)(GSVector3 minP))factory
{
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
        
#if 0
        OSAtomicIncrement32Barrier(&n);
        float load = (float)n / numBuckets;
        NSLog(@"hash table load = %.3f", load);
#endif
    }
    
    [lock unlock];
    
    return anObject;
}

@end
