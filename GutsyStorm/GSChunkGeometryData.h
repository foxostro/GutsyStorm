//
//  GSChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSGridItem.h"
#import "GSVoxel.h"
#import "GSTerrainVertex.h"


@class GSNeighborhood;
@class GSBlockMesh;
@class GSChunkSunlightData;


@interface GSChunkGeometryData : NSObject <GSGridItem>

+ (nonnull NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP;

/* Returns the shared block mesh factory for the specified voxel type. */
+ (nonnull GSBlockMesh *)sharedMeshFactoryWithBlockType:(GSVoxelType)type;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nonnull NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                               trace:(nullable struct GSStopwatchTraceState *)trace;

/* Copy the chunk vertex buffer to a new buffer and return it.
 * Return the number of vertices in the buffer in `count'
 */
- (nonnull GSTerrainVertexNoNormal *)copyVertsReturningCount:(nonnull GLsizei *)count;

@end
