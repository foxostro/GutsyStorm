//
//  GSChunkData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSGridItem.h"

@interface GSChunkData : NSObject <GSGridItem>

@property (readonly, nonatomic) GLKVector3 minP;

- (id)initWithMinP:(GLKVector3)minP;

@end