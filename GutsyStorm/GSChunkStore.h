//
//  GSChunkStore.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSVector3.h"
#import "GSChunk.h"
#import "GSCamera.h"

@interface GSChunkStore : NSObject
{
    NSCache *cache;
    float terrainHeight;
    unsigned seed;
    GSVector3 activeRegionMinP, activeRegionMaxP; // The active region is positioned relative to the camera.
    GSCamera *camera;
}

- (id)initWithSeed:(unsigned)seed camera:(GSCamera *)camera;
- (void)draw;
- (void)updateWithDeltaTime:(float)dt;
- (GSChunk *)getChunkAtPoint:(GSVector3)p;

@end
