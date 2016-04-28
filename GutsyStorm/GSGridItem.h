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

@required

/* The minimum corner of the item, which is a rectangular prism (box). */
@property (readonly, nonatomic) vector_float3 minP;

/* The cost of the item for use in grids which enforce cost limits. */
@property (readonly, nonatomic) NSUInteger cost;

@end

/* This block defines a factory to generate new grid item objects given only the unique minP of the item. */
typedef NSObject<GSGridItem> * (^GSGridItemFactory)(vector_float3 minP);