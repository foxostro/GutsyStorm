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
#import "GSChunkData.h"


@class GSChunkVoxelData;
@class GSNeighborhood;


@interface GSChunkGeometryData : GSChunkData
{
    /* There are two copies of the index buffer so that one can be used for
     * drawing the chunk while geometry generation is in progress. This
     * removes the need to have any locking surrounding access to data
     * related to VBO drawing.
     */
    
    BOOL needsVBORegeneration;
    GLsizei numIndicesForDrawing;
    GLuint *indexBufferForDrawing; // Index buffer which is used when rendering VBOs.
    GLuint vboChunkVerts, vboChunkNorms, vboChunkTexCoords, vboChunkColors;
    
    NSConditionLock *lockGeometry;
    GLsizei numChunkVerts;
    GLfloat *vertsBuffer;
    GLfloat *normsBuffer;
    GLfloat *texCoordsBuffer;
    GLfloat *colorBuffer;
    GLsizei numIndicesForGenerating;
    GLuint *indexBufferForGenerating; // Index buffer which is filled by the geometry generation routine.
    
    NSOpenGLContext *glContext;
    dispatch_queue_t chunkTaskQueue;
    
 @public
    GSVector3 corners[8];
    BOOL visible; // Used by GSChunkStore to note chunks it has determined are visible.
}


- (id)initWithMinP:(GSVector3)_minP
         voxelData:(GSNeighborhood *)neighborhood
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         glContext:(NSOpenGLContext *)_glContext;

- (void)updateWithVoxelData:(GSNeighborhood *)neighborhood doItSynchronously:(BOOL)sync;

- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration;

@end
