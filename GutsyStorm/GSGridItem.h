//
//  GSGridItem.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/12/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <simd/vector.h>


/* Grid Items are objects which are inserted into a grid slot. These are all intended to be immutable objects. */
@protocol GSGridItem <NSCopying>

/* The minimum corner of the item, which is a rectangular prism (box). */
@property (readonly, nonatomic) vector_float3 minP;

/* Invalidate the grid item.
 * Useful when replacing this item with a new item.
 */
- (void)invalidate;

@end


/* This block defines a factory to generate new grid item objects given only the unique minP of the item. */
typedef NSObject<GSGridItem> * (^GSGridItemFactory)(vector_float3 minP);