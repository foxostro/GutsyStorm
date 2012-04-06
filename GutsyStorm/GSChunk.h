//
//  GSChunk.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

#import "GSVector3.h"
#import "GSRay.h"

#define CHUNK_SIZE_X (32)
#define CHUNK_SIZE_Y (512)
#define CHUNK_SIZE_Z (32)


@interface GSChunk : NSObject
{
    GSVector3 minP;
    GSVector3 maxP;
    
    GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords;
    GLsizei numElementsInVBO; // This is numChunkVerts*3, but use a copy so we won't have to lock geometry to get it.
    
    NSConditionLock *lockGeometry;
    GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
    
    NSConditionLock *lockVoxelData;
    BOOL *voxelData;

 @public
    GSVector3 corners[8];
	BOOL visible;
	BOOL visibleForCubeMap[6];
}

@property (readonly, nonatomic) GSVector3 minP;
@property (readonly, nonatomic) GSVector3 maxP;

+ (NSString *)computeChunkFileNameWithMinP:(GSVector3)minP;

- (id)initWithSeed:(unsigned)seed
              minP:(GSVector3)minP
     terrainHeight:(float)terrainHeight
			folder:(NSURL *)folder;
- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration;
- (void)saveToFileWithContainingFolder:(NSURL *)folder;
- (void)loadFromFile:(NSURL *)url;
- (BOOL)rayHitsChunk:(GSRay)ray intersectionDistanceOut:(float *)intersectionDistanceOut;

@end
