//
//  GSGridSunlight.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"

@interface GSGridSunlight : GSGrid

- (instancetype)initWithName:(NSString *)name
                 cacheFolder:(NSURL *)folder
                     factory:(grid_item_factory_t)factory;

@end