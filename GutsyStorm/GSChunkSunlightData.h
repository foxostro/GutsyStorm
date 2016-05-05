//
//  GSChunkSunlightData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"


@class GSTerrainBuffer;
@class GSVoxelNeighborhood;


@interface GSChunkSunlightData : NSObject <GSGridItem>

@property (readonly, nonatomic, nonnull) GSTerrainBuffer *sunlight;
@property (readonly, nonatomic, nonnull) GSVoxelNeighborhood *neighborhood;

+ (nonnull NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood
                        allowLoading:(BOOL)allowLoading;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        sunlightData:(nonnull GSTerrainBuffer *)updatedSunlightData
                        neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood;

- (nonnull instancetype)copyReplacingSunlightData:(nonnull GSTerrainBuffer *)updatedSunlightData
                                     neighborhood:(nonnull GSVoxelNeighborhood *)neighborhood;

@end
