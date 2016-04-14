//
//  GSChunkSunlightData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"


@class GSNeighborhood;
@class GSTerrainBuffer;


@interface GSChunkSunlightData : NSObject <GSGridItem>

@property (readonly, nonatomic, nonnull) GSTerrainBuffer * sunlight;
@property (readonly, nonatomic, nonnull) GSNeighborhood * neighborhood;

+ (nonnull NSString *)fileNameForSunlightDataFromMinP:(vector_float3)minP;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                         neighborhood:(nonnull GSNeighborhood *)neighborhood;

@end
