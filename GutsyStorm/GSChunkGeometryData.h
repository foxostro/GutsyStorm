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
    BOOL dirty;
    int updateInFlight;
    
    NSOpenGLContext *glContext;
    
 @public
    GSVector3 corners[8];
    BOOL visible; // Used by GSChunkStore to note chunks it has determined are visible.
}

@property (assign) BOOL dirty;

- (id)initWithMinP:(GSVector3)_minP glContext:(NSOpenGLContext *)_glContext;

/* Try to immediately update geometry using voxel data for the local neighborhood. If it is not possible to immediately take all
 * the locks on necessary resources then this method aborts the update and returns NO. If it is able to complete the update
 * successfully then it returns YES and marks this GSChunkGeometryData as being clean. (dirty=NO)
 */
- (BOOL)tryToUpdateWithVoxelData:(GSNeighborhood *)neighborhood;

- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration;

@end
