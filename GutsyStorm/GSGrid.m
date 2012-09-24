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
    self = [super init];
    if (self) {
        lockMap = [[NSLock alloc] init];
        mapPosToObject = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [lockMap release];
    [mapPosToObject release];
    [super dealloc];
}

- (id)objectAtPoint:(GSVector3)p objectFactory:(id (^)(GSVector3 minP))factory
{
    id anObject;
    
    GSVector3 minP = [GSChunkData minCornerForChunkAtPoint:p];
    chunk_id_t aKey = [GSChunkData chunkIDWithChunkMinCorner:minP];
    
    [lockMap lock];
    
    anObject = [mapPosToObject objectForKey:aKey];
    if(!anObject) {
        anObject = factory(minP);
        assert(anObject);
        [mapPosToObject setObject:anObject forKey:aKey];
    }
    
    [lockMap unlock];
    
    return anObject;
}

@end
