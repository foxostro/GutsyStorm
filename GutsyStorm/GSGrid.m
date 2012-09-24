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
        lockAllBuckets = [[NSLock alloc] init];
        numBuckets = 1024;
        buckets = malloc(numBuckets * sizeof(NSMutableArray *));
        
        for(NSUInteger i=0; i<numBuckets; ++i)
        {
            buckets[i] = [[NSMutableArray alloc] init];
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
    
    [lockAllBuckets release];
    free(buckets);
    [super dealloc];
}

- (id)_objectForKey:(chunk_id_t)aKey
{
    NSMutableArray *bucket = buckets[[aKey hash] % numBuckets];
    for(GSGridItem *item in bucket)
    {
        if([item.aKey isEqual:aKey])
        {
            return item.anObject;
        }
    }
    
    return nil;
}

- (void)_setObject:(id)anObject forKey:(id)aKey
{
    assert(![self _objectForKey:aKey]);
    GSGridItem *item = [[[GSGridItem alloc] initWithKey:aKey object:anObject] autorelease];
    NSMutableArray *bucket = buckets[[aKey hash] % numBuckets];
    [bucket addObject:item];
}

- (id)objectAtPoint:(GSVector3)p objectFactory:(id (^)(GSVector3 minP))factory
{
    id anObject;
    
    GSVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    chunk_id_t aKey = [GSChunkData chunkIDWithChunkMinCorner:minP];
    
    [lockAllBuckets lock];
    
    anObject = [self _objectForKey:aKey];
    if(!anObject) {
        anObject = factory(minP);
        assert(anObject);
        [self _setObject:anObject forKey:aKey];
    }
    
    [lockAllBuckets unlock];
    
    return anObject;
}

@end
