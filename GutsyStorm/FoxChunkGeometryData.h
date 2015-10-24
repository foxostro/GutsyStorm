//
//  FoxChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import "FoxGridItem.h"
#import "GSVoxel.h"


struct GSTerrainVertex;
@class FoxNeighborhood;
@class FoxBlockMesh;
@class FoxChunkSunlightData;


@interface FoxChunkGeometryData : NSObject <FoxGridItem>

+ (nonnull NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP;

/* Returns the shared block mesh factory for the specified voxel type. */
+ (nonnull FoxBlockMesh *)sharedMeshFactoryWithBlockType:(GSVoxelType)type;

- (nullable instancetype)initWithMinP:(vector_float3)minCorner
                               folder:(nonnull NSURL *)folder
                             sunlight:(nonnull FoxChunkSunlightData *)sunlight;

/* Copy the chunk vertex buffer to a new buffer and return that in `dst'. Return the number of vertices in the buffer. */
- (GLsizei)copyVertsToBuffer:(struct GSTerrainVertex * _Nonnull * _Nonnull)dst;

@end
