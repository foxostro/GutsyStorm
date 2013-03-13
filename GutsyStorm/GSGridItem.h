//
//  GSGridItem.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Chunk.h"

@protocol GSGridItem <NSObject>
@required
@property (readonly, nonatomic) GLKVector3 minP;
@end