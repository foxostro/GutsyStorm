//
//  GSNeighborhood.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVoxel.h" // for GSVoxelNeighborIndex


@class GSTerrainBuffer;


@interface GSNeighborhood<__covariant ObjectType> : NSObject

+ (vector_float3)offsetForNeighborIndex:(GSVoxelNeighborIndex)idx;

- (nonnull ObjectType)neighborAtIndex:(GSVoxelNeighborIndex)idx;
- (void)setNeighborAtIndex:(GSVoxelNeighborIndex)idx neighbor:(nonnull ObjectType)neighbor;

/* Copy the neighborhood but replace the instance of `original' with `replacement'. */
- (nonnull instancetype)copyReplacing:(nonnull ObjectType)original withNeighbor:(nonnull ObjectType)replacement;

@end