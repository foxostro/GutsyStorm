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
#import "FoxVoxel.h"
#import "FoxTerrainBuffer.h"


typedef void (^terrain_generator_t)(vector_float3, voxel_t*);
typedef void (^terrain_post_processor_t)(size_t count, voxel_t *voxels, vector_long3 minP, vector_long3 maxP);


@interface FoxChunkVoxelData : NSObject <FoxGridItem>

@property (readonly, nonatomic) FoxTerrainBuffer *voxels;

+ (NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP;

- (instancetype)initWithMinP:(vector_float3)minP
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                   generator:(terrain_generator_t)generator
               postProcessor:(terrain_post_processor_t)postProcessor;

- (instancetype)initWithMinP:(vector_float3)minP
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                        data:(FoxTerrainBuffer *)data;

- (voxel_t)voxelAtLocalPosition:(vector_long3)chunkLocalP;

- (void)saveToFile;

- (FoxChunkVoxelData *)copyWithEditAtPoint:(vector_float3)pos block:(voxel_t)newBlock;

@end