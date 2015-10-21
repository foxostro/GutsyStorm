//
//  FoxGridSunlight.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGrid.h"

@interface FoxGridSunlight : FoxGrid<FoxChunkSunlightData *>

- (instancetype)initWithName:(NSString *)name
                 cacheFolder:(NSURL *)folder
                     factory:(fox_grid_item_factory_t)factory;

@end