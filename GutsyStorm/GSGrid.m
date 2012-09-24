//
//  GSGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 9/23/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSGrid.h"
#import "GSChunkData.h"

/*********************************************************************************************************************************/

@interface GSGridItem : NSObject
{
    id aKey;
    id anObject;
}

@property (readonly) id aKey;
@property (readonly) id anObject;

- (id)initWithKey:(id)_aKey object:(id)_anObject;

@end

/*********************************************************************************************************************************/

@implementation GSGridItem

@synthesize aKey;
@synthesize anObject;

- (id)initWithKey:(id)_aKey object:(id)_anObject
{
    self = [super init];
    if (self) {
        aKey = [_aKey copyWithZone:NULL];
        anObject = _anObject;
        [anObject retain];
    }
    
    return self;
}

- (void)dealloc
{
    [aKey release];
    [anObject release];
    [super dealloc];
}

@end

/*********************************************************************************************************************************/

@implementation GSGrid

- (id)init
{
    self = [super init];
    if (self) {
        numBuckets = 8192; // TODO: this value is chosen arbitrarily. Choose hash table size more intelligently.
        
        buckets = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            buckets[i] = [[NSMutableArray alloc] init];
        }
        
        locks = malloc(numBuckets * sizeof(NSMutableArray *));
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            locks[i] = [[NSLock alloc] init];
        }
    }
    
    return self;
}

- (void)dealloc
{
    for(NSUInteger i=0; i<numBuckets; ++i)
    {
        [buckets[i] release];
    }
    
    for(NSUInteger i=0; i<numBuckets; ++i)
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
    chunk_id_t aKey = [GSChunkData chunkIDWithChunkMinCorner:minP];
    NSUInteger idx = [aKey hash] % numBuckets;
    NSLock *lock = locks[idx];
    NSMutableArray *bucket = buckets[idx];
    
    [lock lock];
    
    for(GSGridItem *item in bucket)
    {
        if([item.aKey isEqual:aKey])
        {
            anObject = item.anObject;
        }
    }
    
    if(!anObject) {
        anObject = factory(minP);
        assert(anObject);
        [bucket addObject:[[[GSGridItem alloc] initWithKey:aKey object:anObject] autorelease]];
    }
    
    [lock unlock];
    
    return anObject;
}

@end
