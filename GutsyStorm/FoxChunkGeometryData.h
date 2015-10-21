//
//  FoxChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>
#import "FoxGridItem.h"
#import "FoxVoxel.h"


struct fox_vertex;
@class FoxNeighborhood;
@class FoxBlockMesh;
@class FoxChunkSunlightData;


@interface FoxChunkGeometryData : NSObject <FoxGridItem>

+ (NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP;

/* Returns the shared block mesh factory for the specified voxel type. */
+ (FoxBlockMesh *)sharedMeshFactoryWithBlockType:(voxel_type_t)type;

- (instancetype)initWithMinP:(vector_float3)minCorner
                      folder:(NSURL *)folder
                    sunlight:(FoxChunkSunlightData *)sunlight;

/* Copy the chunk vertex buffer to a new buffer and return that in `dst'. Return the number of vertices in the buffer. */
- (GLsizei)copyVertsToBuffer:(struct fox_vertex **)dst;

@end
