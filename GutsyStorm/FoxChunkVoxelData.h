//
//  FoxChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGridItem.h"
#import "FoxIntegerVector3.h"
#import "GSVoxel.h"
#import "FoxTerrainBuffer.h"


typedef void (^terrain_generator_t)(vector_float3, GSVoxel * _Nonnull);
typedef void (^terrain_post_processor_t)(size_t count, GSVoxel * _Nonnull voxels, vector_long3 minP, vector_long3 maxP);


@interface FoxChunkVoxelData : NSObject <FoxGridItem>

@property (nonatomic, readonly) FoxTerrainBuffer * _Nonnull voxels;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP;

- (nullable instancetype)initWithMinP:(vector_float3)minP
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                       chunkTaskQueue:(nonnull dispatch_queue_t)chunkTaskQueue
                            generator:(nonnull terrain_generator_t)generator
                        postProcessor:(nonnull terrain_post_processor_t)postProcessor;

- (nullable instancetype)initWithMinP:(vector_float3)minP
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                       chunkTaskQueue:(nonnull dispatch_queue_t)chunkTaskQueue
                                 data:(nonnull FoxTerrainBuffer *)data;

- (GSVoxel)voxelAtLocalPosition:(vector_long3)chunkLocalP;

- (void)saveToFile;

- (nonnull FoxChunkVoxelData *)copyWithEditAtPoint:(vector_float3)pos block:(GSVoxel)newBlock;

@end