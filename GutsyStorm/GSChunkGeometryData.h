//
//  GSChunkGeometryData.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>
#import "GSGridItem.h"
#import "Voxel.h"


struct vertex;
@class GSNeighborhood;
@class GSBlockMesh;


@interface GSChunkGeometryData : NSObject <GSGridItem>

+ (NSString *)fileNameForGeometryDataFromMinP:(GLKVector3)minP;

/* Returns the shared block mesh factory for the specified voxel type. */
+ (GSBlockMesh *)sharedMeshFactoryWithBlockType:(voxel_type_t)type;

- (id)initWithMinP:(GLKVector3)minCorner
            folder:(NSURL *)folder
      neighborhood:(GSNeighborhood *)neighborhood;

/* Copy the chunk vertex buffer to a new buffer and return that in `dst'. Return the number of vertices in the buffer. */
- (GLsizei)copyVertsToBuffer:(struct vertex **)dst;

@end
