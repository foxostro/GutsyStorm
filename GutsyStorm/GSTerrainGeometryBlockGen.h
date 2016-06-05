//
//  GSTerrainGeometryBlockGen.h
//  GutsyStorm
//
//  Created by Andrew Fox on 6/5/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSTerrainGeometryGeneratorInternal.h"

void GSTerrainGeometryBlockGen(GSTerrainGeometry * _Nonnull geometry,
                               GSVoxel * _Nonnull voxels,
                               GSIntAABB voxelBox,
                               vector_float3 chunkMinP,
                               GSIntAABB ibounds);