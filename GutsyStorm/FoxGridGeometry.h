//
//  FoxGridGeometry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

@interface FoxGridGeometry : FoxGrid

- (instancetype)initWithName:(NSString *)name
                 cacheFolder:(NSURL *)folder
                     factory:(fox_grid_item_factory_t)factory;

@end