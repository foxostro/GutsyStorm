//
//  FoxChunkSunlightData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGridItem.h"


@class FoxNeighborhood;
@class FoxTerrainBuffer;


@interface FoxChunkSunlightData : NSObject <FoxGridItem>

@property (readonly, nonatomic) FoxTerrainBuffer *sunlight;
@property (readonly, nonatomic) FoxNeighborhood *neighborhood;

+ (NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP;

- (instancetype)initWithMinP:(vector_float3)minCorner
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                neighborhood:(FoxNeighborhood *)neighborhood;

@end
