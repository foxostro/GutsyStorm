//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSChunkGeometryData.h"

@interface GSActiveRegion : NSObject
{
    GSVector3 activeRegionExtent; // The active region is specified relative to the camera position.
    NSUInteger maxActiveChunks;
    GSChunkGeometryData **activeChunks;
    NSLock *lock;
}

@property (readonly, nonatomic) NSUInteger maxActiveChunks;

- (id)initWithActiveRegionExtent:(GSVector3)activeRegionExtent;
- (void)forEachChunkDoBlock:(void (^)(GSChunkGeometryData *))block;
- (void)removeAllActiveChunks;
- (void)setActiveChunk:(GSChunkGeometryData *)chunk atIndex:(NSUInteger)idx;
- (GSVector3)randomPointInActiveRegionWithCameraPos:(GSVector3)cameraEye;

@end
