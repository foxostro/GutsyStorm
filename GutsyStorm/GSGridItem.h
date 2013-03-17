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
/* TODO:
- (id)copyWithZone:(NSZone *)zone; // TODO: make GSGridItem inherit from NSCopying, not NSObject
@optional
- (void)saveToFile:(NSString *)path;
 */
@end

typedef NSObject <GSGridItem> * (^grid_item_factory_t)(GLKVector3 minP);