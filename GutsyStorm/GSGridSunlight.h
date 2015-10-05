//
//  GSGridSunlight.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSGridSunlight : GSGrid

- (instancetype)initWithCacheFolder:(NSURL *)folder factory:(grid_item_factory_t)factory;

@end
