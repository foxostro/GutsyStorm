//
//  GSChunkData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSBuffer.h" // for buffer_element_t
#import "Voxel.h"
#import "GSIntegerVector3.h"
#import "GutsyStormErrorCodes.h"


#define READY (1)

extern const GSIntegerVector3 chunkSize;
extern const GSIntegerVector3 offsetForFace[FACE_NUM_FACES];

typedef id chunk_id_t;


@interface GSChunkData : NSObject <GSGridItem>

@property (readonly, nonatomic) GLKVector3 minP;
@property (readonly, nonatomic) GLKVector3 maxP;
@property (readonly, nonatomic) GLKVector3 centerP;

+ (GLKVector3)centerPointOfChunkAtPoint:(GLKVector3)p;
+ (chunk_id_t)chunkIDWithChunkMinCorner:(GLKVector3)minP;

- (id)initWithMinP:(GLKVector3)minP;

@end