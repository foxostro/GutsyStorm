//
//  GSChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
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

- (nullable instancetype)initWithMinP:(vector_float3)minCorner
                               folder:(nonnull NSURL *)folder
                             sunlight:(nonnull GSChunkSunlightData *)sunlight;

/* Copy the chunk vertex buffer to a new buffer and return that in `dst'. Return the number of vertices in the buffer. */
- (GLsizei)copyVertsToBuffer:(GSTerrainVertex * _Nonnull * _Nonnull)dst;

@end
