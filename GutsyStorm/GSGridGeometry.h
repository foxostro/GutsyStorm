//
//  GSGridGeometry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

@interface GSGridGeometry : GSGrid<GSChunkGeometryData *>

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                         cacheFolder:(nonnull NSURL *)folder
                             factory:(nonnull GSGridItemFactory)factory;

@end