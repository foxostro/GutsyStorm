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

- (id)initWithMinP:(GLKVector3)minCorner
            folder:(NSURL *)folder
      neighborhood:(GSNeighborhood *)neighborhood;

@end
