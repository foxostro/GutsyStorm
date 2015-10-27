//
//  GSChunkSunlightData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"


@class GSNeighborhood;
@class GSTerrainBuffer;


@interface GSChunkSunlightData : NSObject <GSGridItem>

@property (readonly, nonatomic) GSTerrainBuffer * _Nonnull sunlight;
@property (readonly, nonatomic) GSNeighborhood * _Nonnull neighborhood;

+ (nonnull NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP;

- (nullable instancetype)initWithMinP:(vector_float3)minCorner
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                       chunkTaskQueue:(nonnull dispatch_queue_t)chunkTaskQueue
                         neighborhood:(nonnull GSNeighborhood *)neighborhood;

@end
