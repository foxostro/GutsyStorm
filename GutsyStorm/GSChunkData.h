//
//  GSChunkData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"

#define CHUNK_SIZE_X (16)
#define CHUNK_SIZE_Y (128)
#define CHUNK_SIZE_Z (16)
#define READY (1)


@interface GSChunkData : NSObject
{
    GSVector3 minP;
    GSVector3 maxP;
    GSVector3 centerP;
}

@property (readonly, nonatomic) GSVector3 minP;
@property (readonly, nonatomic) GSVector3 maxP;
@property (readonly, nonatomic) GSVector3 centerP;

- (id)initWithMinP:(GSVector3)minP;

@end
