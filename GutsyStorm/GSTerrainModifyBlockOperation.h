//
//  GSTerrainModifyBlockOperation.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/2/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "GSVoxel.h"


@class GSTerrainChunkStore;
@class GSTerrainJournal;


@interface GSTerrainModifyBlockOperation : NSOperation

- (nonnull instancetype)init NS_UNAVAILABLE;
- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
                                     block:(GSVoxel)block
                                  position:(vector_float3)pos
                                   journal:(nullable GSTerrainJournal *)journal NS_DESIGNATED_INITIALIZER;

@end
