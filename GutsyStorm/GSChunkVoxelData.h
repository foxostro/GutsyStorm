//
//  GSChunkVoxelData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSIntegerVector3.h"
#import "GSVoxel.h"


@class GSTerrainJournal;
@class GSTerrainBuffer;


typedef void (^GSTerrainProcessorBlock)(size_t count, GSVoxel * _Nonnull voxels,
                                        vector_long3 minP, vector_long3 maxP,
                                        vector_float3 offsetToWorld);


@interface GSChunkVoxelData : NSObject <GSGridItem>

@property (nonatomic, readonly, nonnull) GSTerrainBuffer * voxels;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP;

- (nonnull instancetype)initWithMinP:(vector_float3)minP
                              folder:(nonnull NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                             journal:(nonnull GSTerrainJournal *)journal
                           generator:(nonnull GSTerrainProcessorBlock)generator;

- (nonnull instancetype)initWithMinP:(vector_float3)minP
                               folder:(nonnull NSURL *)folder
                       groupForSaving:(nonnull dispatch_group_t)groupForSaving
                       queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                                 data:(nonnull GSTerrainBuffer *)data;

- (GSVoxel)voxelAtLocalPosition:(vector_long3)chunkLocalP;

- (void)saveToFile;

- (nonnull GSChunkVoxelData *)copyWithEditAtPoint:(vector_float3)pos block:(GSVoxel)newBlock;

@end