//
//  GSGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/23/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GLKVector3Extra.h" // for GLKVector3_Hash
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
        const size_t k = 6; // Experimentation shows this is the minimum to avoid a table resize during app launch.
        numBuckets = k * areaXZ;
        n = 0;
        loadLevelToTriggerResize = 0.80;
        
        buckets = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            buckets[i] = [[NSMutableArray alloc] init];
        }
        
        locks = malloc(numLocks * sizeof(NSLock *));
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
            NSUInteger hash = GLKVector3Hash(item.minP);
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

- (id)objectAtPoint:(GLKVector3)p objectFactory:(id (^)(GLKVector3 minP))factory
{
    [lockTheTableItself lockForReading]; // The only writer is -resizeTable, so lock contention will be low, hopefully.
    
    float load = 0;
    id anObject = nil;
    GLKVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % numBuckets;
    NSUInteger idxLock = hash % numLocks;
    NSLock *lock = locks[idxLock];
    NSMutableArray *bucket = buckets[idxBucket];
    
    [lock lock];
    
    for(GSChunkData *item in bucket)
    {
        if(GLKVector3AllEqualToVector3(item.minP, minP)) {
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

- (BOOL)tryToGetObjectAtPoint:(GLKVector3)p object:(id *)object objectFactory:(id (^)(GLKVector3 minP))factory
{
    // XXX: try to refactor to consolidate this and the objectAtPoint method.
    assert(object);

    if(![lockTheTableItself tryLockForReading]) {
        return NO;
    }

    float load = 0;
    id anObject = nil;
    GLKVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % numBuckets;
    NSUInteger idxLock = hash % numLocks;
    NSLock *lock = locks[idxLock];
    NSMutableArray *bucket = buckets[idxBucket];

    if(![lock tryLock]) {
        [lockTheTableItself unlockForReading];
        return NO;
    }

    for(GSChunkData *item in bucket)
    {
        if(GLKVector3AllEqualToVector3(item.minP, minP)) {
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

    *object = anObject;
    return YES;
}

@end
