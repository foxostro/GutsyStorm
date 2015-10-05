//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSIntegerVector3.h"
#import "Voxel.h"
#import "GSBuffer.h"


typedef void (^terrain_generator_t)(GLKVector3, voxel_t*);
typedef void (^terrain_post_processor_t)(size_t count, voxel_t *voxels, GSIntegerVector3 minP, GSIntegerVector3 maxP);


@interface GSChunkVoxelData : NSObject <GSGridItem>

@property (readonly, nonatomic) GSBuffer *voxels;

+ (NSString *)fileNameForVoxelDataFromMinP:(GLKVector3)minP;

- (instancetype)initWithMinP:(GLKVector3)minP
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                   generator:(terrain_generator_t)generator
               postProcessor:(terrain_post_processor_t)postProcessor;

- (instancetype)initWithMinP:(GLKVector3)minP
                      folder:(NSURL *)folder
              groupForSaving:(dispatch_group_t)groupForSaving
              queueForSaving:(dispatch_queue_t)queueForSaving
              chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
                        data:(GSBuffer *)data;

- (voxel_t)voxelAtLocalPosition:(GSIntegerVector3)chunkLocalP;

- (void)saveToFile;

- (GSChunkVoxelData *)copyWithEditAtPoint:(GLKVector3)pos block:(voxel_t)newBlock;

@end