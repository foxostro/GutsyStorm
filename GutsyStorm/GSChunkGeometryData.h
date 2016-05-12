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
#import "GSBoxedTerrainVertex.h"
#import "GSAABB.h"


@class GSNeighborhood;
@class GSBlockMesh;
@class GSChunkSunlightData;


#define GSNumGeometrySubChunks (16)
_Static_assert(CHUNK_SIZE_Y % GSNumGeometrySubChunks == 0,
               "Chunk size must be evenly divisible by the number of geometry sub-chunks");


@interface GSChunkGeometryData : NSObject <GSGridItem>
{
@private
    NSArray<GSBoxedTerrainVertex *> *_vertices[GSNumGeometrySubChunks];

    NSData *_data;
    NSURL *_folder;
    dispatch_group_t _groupForSaving;
    dispatch_queue_t _queueForSaving;
}

+ (nonnull NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        allowLoading:(BOOL)allowLoading;

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nullable NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                            vertices:(NSArray * __strong _Nonnull [GSNumGeometrySubChunks])vertices
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving;

- (nonnull instancetype)copyWithSunlight:(nonnull GSChunkSunlightData *)sunlight
                       invalidatedRegion:(GSIntAABB * _Nonnull)invalidatedRegion;

/* Copy the chunk vertex buffer to a new buffer and return it.
 * Return the number of vertices in the buffer in `count'
 */
- (nonnull GSTerrainVertexNoNormal *)copyVertsReturningCount:(nonnull GLsizei *)count;

@end
