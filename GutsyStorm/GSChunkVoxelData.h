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
@class GSTerrainGenerator;


@interface GSChunkVoxelData : NSObject <GSGridItem>

@property (nonatomic, readonly, nonnull) GSTerrainBuffer * voxels;

+ (nonnull NSString *)fileNameForVoxelDataFromMinP:(vector_float3)minP;

- (nonnull instancetype)initWithMinP:(vector_float3)minP
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                             journal:(nullable GSTerrainJournal *)journal
                           generator:(nonnull GSTerrainGenerator *)generator
                        allowLoading:(BOOL)allowLoading;

- (nonnull instancetype)initWithMinP:(vector_float3)minP
                              folder:(nullable NSURL *)folder
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                                data:(nonnull GSTerrainBuffer *)data
                             editPos:(vector_float3)pos
                            oldBlock:(GSVoxel)oldBlock;

- (GSVoxel)voxelAtLocalPosition:(vector_long3)chunkLocalP;

- (void)saveToFile;

- (nonnull instancetype)copyWithEditAtPoint:(vector_float3)pos
                                      block:(GSVoxel)newBlock
                                  operation:(GSVoxelBitwiseOp)op;

@end