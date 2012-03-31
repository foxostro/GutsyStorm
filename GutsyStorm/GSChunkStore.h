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
    GSCamera *camera;
	NSURL *folder;
	
	size_t maxActiveChunks;
	GSChunk **activeChunks, **tmpActiveChunks;
    GSVector3 activeRegionExtent; // The active region is positioned relative to the camera.
}

- (id)initWithSeed:(unsigned)seed camera:(GSCamera *)camera;
- (void)draw;
- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)cameraModifiedFlags;
- (GSChunk *)getChunkAtPoint:(GSVector3)p;

@end
