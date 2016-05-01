//
//  GSTerrainGenerator.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVoxel.h"


@interface GSTerrainGenerator : NSObject

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithRandomSeed:(NSInteger)seed NS_DESIGNATED_INITIALIZER;

- (void)generateWithDestination:(nonnull GSVoxel *)voxels
                          count:(NSUInteger)count
                      minCorner:(vector_long3)minP
                      maxCorner:(vector_long3)maxP
                  offsetToWorld:(vector_float3)offsetToWorld;

@end
