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
        activeRegionExtent = GSVector3_Make(128, terrainHeight/2.0, 128);
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
    GSVector3 p, minP, maxP;
    GSFrustum *frustum = [camera frustum];
    
    minP = GSVector3_Sub([camera cameraEye], activeRegionExtent);
    maxP = GSVector3_Add([camera cameraEye], activeRegionExtent);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
    // Draw all visible chunks that fall within the active region.
    for(p.x = minP.x; p.x < maxP.x; p.x += CHUNK_SIZE_X)
    {
        for(p.z = minP.z; p.z < maxP.z; p.z += CHUNK_SIZE_Z)
        {
            GSChunk *chunk = [self getChunkAtPoint:p];
            if(GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:chunk->corners]) {
                [chunk draw];
            }
        }
    }
    
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
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
        /*char buffer[64] = {0};
        GSVector3_ToString(buffer, sizeof(buffer), minP);
        NSLog(@"Need to fetch another chunk; chunkID=%@, minP=%s", chunkID, buffer);*/
        
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
	return [NSString stringWithFormat:@"%d_%d_%d", (int)minP.x, (int)minP.y, (int)minP.z];
}

@end
