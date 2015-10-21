//
//  FoxGridGeometry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

@interface FoxGridGeometry : FoxGrid<FoxChunkGeometryData *>

- (nullable instancetype)initWithName:(nonnull NSString *)name
                          cacheFolder:(nonnull NSURL *)folder
                              factory:(nonnull fox_grid_item_factory_t)factory;

@end