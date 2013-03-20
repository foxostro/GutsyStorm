//
//  GSActiveRegion.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/14/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

@class GSCamera;
@class GSFrustum;
@class GSChunkVBOs;


@interface GSActiveRegion : NSObject

@property (readonly, nonatomic) NSUInteger maxActiveChunks;

- (id)initWithActiveRegionExtent:(GLKVector3)activeRegionExtent;
- (void)updateWithCameraModifiedFlags:(unsigned)flags
                               camera:(GSCamera *)camera
                        chunkProducer:(GSChunkVBOs * (^)(GLKVector3 p))chunkProducer;
- (void)draw;
- (void)enumerateActiveChunkWithBlock:(void (^)(GSChunkVBOs *))block;
- (NSArray *)pointsListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedPoints;
- (NSArray *)chunksListSortedByDistFromCamera:(GSCamera *)camera unsortedList:(NSMutableArray *)unsortedChunks;
- (void)enumeratePointsInActiveRegionNearCamera:(GSCamera *)camera usingBlock:(void (^)(GLKVector3 p))myBlock;

@end
