//
//  GSChunkData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"
#import "GSIntegerVector3.h"
#import "GutsyStormErrorCodes.h"


#define READY (1)

extern const GSIntegerVector3 chunkSize;

typedef id chunk_id_t;


@interface GSChunkData : NSObject
{
    GSVector3 minP;
    GSVector3 maxP;
    GSVector3 centerP;
}

@property (readonly, nonatomic) GSVector3 minP;
@property (readonly, nonatomic) GSVector3 maxP;
@property (readonly, nonatomic) GSVector3 centerP;

+ (GSVector3)minCornerForChunkAtPoint:(GSVector3)p;
+ (GSVector3)centerPointOfChunkAtPoint:(GSVector3)p;
+ (chunk_id_t)chunkIDWithChunkMinCorner:(GSVector3)minP;

- (id)initWithMinP:(GSVector3)minP;

@end
