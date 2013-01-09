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
{
    GSReaderWriterLock *_lockTheTableItself; // Lock protects the "buckets" array itself, but not its contents.

    NSUInteger _numBuckets;
    NSMutableArray * __strong *_buckets;

    NSUInteger _numLocks;
    NSLock * __strong *_locks;

    int32_t _n;
    float _loadLevelToTriggerResize;
}

- (id)init
{
    return [self initWithActiveRegionArea:1024];
}

- (id)initWithActiveRegionArea:(size_t)areaXZ
{
    self = [super init];
    if (self) {
        _numLocks = [[NSProcessInfo processInfo] processorCount] * 64;
        const size_t k = 6; // Experimentation shows this is the minimum to avoid a table resize during app launch.
        _numBuckets = k * areaXZ;
        _n = 0;
        _loadLevelToTriggerResize = 0.80;
        
        _buckets = (NSMutableArray * __strong *)calloc(_numBuckets, sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<_numBuckets; ++i)
        {
            _buckets[i] = [[NSMutableArray alloc] init];
        }
        
        _locks = (NSLock * __strong *)calloc(_numLocks, sizeof(NSLock *));
        for(NSUInteger i=0; i<_numLocks; ++i)
        {
            _locks[i] = [[NSLock alloc] init];
        }
        
        _lockTheTableItself = [[GSReaderWriterLock alloc] init];
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
    NSMutableArray * __strong *oldBuckets = _buckets;
    
    // Allocate memory for a new set of buckets.
    _numBuckets *= 2;
    _buckets = (NSMutableArray * __strong *)calloc(_numBuckets, sizeof(NSMutableArray *));
    for(NSUInteger i=0; i<_numBuckets; ++i)
    {
        _buckets[i] = [[NSMutableArray alloc] init];
    }
    
    // Insert each object into the new hash table.
    for(NSUInteger i=0; i<oldNumBuckets; ++i)
    {
        for(GSChunkData *item in oldBuckets[i])
        {
            NSUInteger hash = GLKVector3Hash(item.minP);
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

- (BOOL)objectAtPoint:(GLKVector3)p
             blocking:(BOOL)blocking
               object:(id *)object objectFactory:(id (^)(GLKVector3 minP))factory
{
    assert(object);

    if(blocking) {
        [_lockTheTableItself lockForReading];
    } else if(![_lockTheTableItself tryLockForReading]) {
        return NO;
    }

    float load = 0;
    id anObject = nil;
    GLKVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    NSUInteger hash = GLKVector3Hash(minP);
    NSUInteger idxBucket = hash % _numBuckets;
    NSUInteger idxLock = hash % _numLocks;
    NSLock *lock = _locks[idxLock];
    NSMutableArray *bucket = _buckets[idxBucket];

    if(blocking) {
        [lock lock];
    } else if(![lock tryLock]) {
        [_lockTheTableItself unlockForReading];
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
        OSAtomicIncrement32Barrier(&_n);
        load = (float)_n / _numBuckets;
    }

    [lock unlock];
    [_lockTheTableItself unlockForReading];

    if(load > _loadLevelToTriggerResize) {
        [self resizeTable];
    }

    *object = anObject;
    return YES;
}

- (id)objectAtPoint:(GLKVector3)p objectFactory:(id (^)(GLKVector3 minP))factory
{
    id anObject = nil;
    [self objectAtPoint:p
               blocking:YES
                 object:&anObject
          objectFactory:factory];
    return anObject;
}

- (BOOL)tryToGetObjectAtPoint:(GLKVector3)p object:(id *)object objectFactory:(id (^)(GLKVector3 minP))factory
{
    return [self objectAtPoint:p
                      blocking:NO
                        object:object
                 objectFactory:factory];
}

@end
