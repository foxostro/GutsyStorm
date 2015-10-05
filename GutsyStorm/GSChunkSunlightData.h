//
//  GSChunkSunlightData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>
#import "GSGridItem.h"


@class GSNeighborhood;
@class GSBuffer;


@interface GSChunkSunlightData : NSObject <GSGridItem>

@property (readonly, nonatomic) GSBuffer *sunlight;
@property (readonly, nonatomic) GSNeighborhood *neighborhood;

+ (NSString *)fileNameForSunlightDataFromMinP:(GLKVector3)minP;

- (instancetype)initWithMinP:(GLKVector3)minCorner
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                neighborhood:(GSNeighborhood *)neighborhood;

@end
