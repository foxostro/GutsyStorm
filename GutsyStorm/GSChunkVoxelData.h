//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSIntegerVector3.h"
#import "GSVoxel.h"
#import "GSTerrainBuffer.h"


typedef void (^GSTerrainGeneratorBlock)(vector_float3, GSVoxel * _Nonnull);
typedef void (^terrain_post_processor_t)(size_t count, GSVoxel * _Nonnull voxels, vector_long3 minP, vector_long3 maxP);


@interface GSChunkVoxelData : NSObject <GSGridItem>

@property (nonatomic, readonly) GSTerrainBuffer * _Nonnull voxels;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP;

- (nullable instancetype)initWithMinP:(vector_float3)minP
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                       chunkTaskQueue:(nonnull dispatch_queue_t)chunkTaskQueue
                            generator:(nonnull GSTerrainGeneratorBlock)generator
                        postProcessor:(nonnull terrain_post_processor_t)postProcessor;

- (nullable instancetype)initWithMinP:(vector_float3)minP
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                       chunkTaskQueue:(nonnull dispatch_queue_t)chunkTaskQueue
                                 data:(nonnull GSTerrainBuffer *)data;

- (GSVoxel)voxelAtLocalPosition:(vector_long3)chunkLocalP;

- (void)saveToFile;

- (nonnull GSChunkVoxelData *)copyWithEditAtPoint:(vector_float3)pos block:(GSVoxel)newBlock;

@end