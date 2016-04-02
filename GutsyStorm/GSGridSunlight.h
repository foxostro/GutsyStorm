//
//  GSGridSunlight.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"

@interface GSGridSunlight : GSGrid<GSChunkSunlightData *>

- (nullable instancetype)initWithName:(nonnull NSString *)name
                          cacheFolder:(nonnull NSURL *)folder
                              factory:(nonnull fox_grid_item_factory_t)factory;

@end