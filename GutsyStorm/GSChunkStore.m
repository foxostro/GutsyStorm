//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import "GSChunkStore.h"


@interface GSChunkStore (Private)

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p;
- (NSString *)getChunkIDWithMinP:(GSVector3)minP;

@end


@implementation GSChunkStore

- (id)initWithSeed:(unsigned)_seed camera:(GSCamera *)_camera
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
        cache = [[NSCache alloc] init];
        camera = _camera;
        [camera retain];
        
        terrainHeight = CHUNK_SIZE_Y;
        activeRegionMinP = GSVector3_Make(0, 0, 0);
        activeRegionMaxP = GSVector3_Make(256, terrainHeight, 256);
    }
    
    return self;
}


- (void)dealloc
{
    [cache release];
    [camera release];
}


- (void)draw
{
    GSVector3 p;
    
    // Draw all chunks that fall within the active region.
    for(p.x = activeRegionMinP.x; p.x < activeRegionMaxP.x; p.x += CHUNK_SIZE_X)
    {
        for(p.y = activeRegionMinP.y; p.y < activeRegionMaxP.y; p.y += CHUNK_SIZE_Y)
        {
            for(p.z = activeRegionMinP.z; p.z < activeRegionMaxP.z; p.z += CHUNK_SIZE_Z)
            {
                [[self getChunkAtPoint:p] draw];
            }
        }
    }
}


- (void)updateWithDeltaTime:(float)dt
{
    // Do nothing
}


- (GSChunk *)getChunkAtPoint:(GSVector3)p
{
    GSChunk *chunk = nil;
    GSVector3 minP = [self computeChunkMinPForPoint:p];
    NSString *chunkID = [self getChunkIDWithMinP:minP];
    
    chunk = [cache objectForKey:chunkID];
    if(!chunk) {
        chunk = [[GSChunk alloc] initWithSeed:seed
                                         minP:minP
                                terrainHeight:terrainHeight];
        [cache setObject:chunk forKey:chunkID];
    }
    
    return chunk;
}

@end


@implementation GSChunkStore (Private)

- (GSVector3)computeChunkMinPForPoint:(GSVector3)p
{
    return GSVector3_Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}


- (NSString *)getChunkIDWithMinP:(GSVector3)minP
{
	return [NSString stringWithFormat:@"%.0f_%.0f_%.0f", minP.x, minP.y, minP.z];
}

@end