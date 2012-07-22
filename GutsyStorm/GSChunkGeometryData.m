//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSChunkGeometryData.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSVertex.h"

#define SWAP(x, y) do { typeof(x) temp##x##y = x; x = y; y = temp##x##y; } while (0)


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo);

static void asyncDestroyChunkVBOs(NSOpenGLContext *context,
                                  GLuint vboChunkVerts,
                                  GLuint vboChunkNorms,
                                  GLuint vboChunkTexCoords,
                                  GLuint vboChunkColors);

static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GSVector3 c,
                      GLfloat **verts,
                      GLfloat **norms,
                      GLfloat **txcds,
                      GLfloat **color);

static GLfloat * allocateGeometryBuffer(size_t numVerts);


static inline GSVector3 blockLight(unsigned sunlight, unsigned torchLight, unsigned ambientOcclusion)
{
    // Pack ambient occlusion into the Red channel, sunlight into the Green channel, and torch light into the Blue channel.
    return GSVector3_Make(ambientOcclusion / (float)CHUNK_MAX_AO_COUNT,
                          (sunlight / (float)CHUNK_LIGHTING_MAX) * 0.7f + 0.3f,
                          torchLight / (float)CHUNK_LIGHTING_MAX);
}


static inline unsigned calcFinalOcclusion(BOOL a, BOOL b, BOOL c, BOOL d)
{
    return (a?1:0) + (b?1:0) + (c?1:0) + (d?1:0);
}


@interface GSChunkGeometryData (Private)

- (BOOL)tryToGenerateVBOs;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)voxels;
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertsBuffer:(GLfloat **)_vertsBuffer
                                        normsBuffer:(GLfloat **)_normsBuffer
                                    texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                        colorBuffer:(GLfloat **)_colorBuffer
                                        indexBuffer:(GLuint **)_indexBuffer
                                          voxelData:(GSChunkVoxelData **)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting;
- (void)fillIndexBufferForGenerating:(GLsizei)n;
- (void)countNeighborsForAmbientOcclusionsAtPoint:(GSIntegerVector3)p
                                        neighbors:(GSChunkVoxelData **)chunks
                              outAmbientOcclusion:(block_lighting_t*)ao;

@end


@implementation GSChunkGeometryData


- (id)initWithMinP:(GSVector3)_minP
         voxelData:(GSChunkVoxelData **)_chunks
    chunkTaskQueue:(dispatch_queue_t)_chunkTaskQueue
         glContext:(NSOpenGLContext *)_glContext
{
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.
        
        chunkTaskQueue = _chunkTaskQueue; // dispatch queue used for chunk background work
        dispatch_retain(_chunkTaskQueue);
        
        glContext = _glContext;
        [glContext retain];
        
        // Geometry for the chunk is protected by lockGeometry and is generated asynchronously.
        lockGeometry = [[NSConditionLock alloc] init];
        [lockGeometry setName:@"GSChunkGeometryData.lockGeometry"];
        vertsBuffer = NULL;
        normsBuffer = NULL;
        texCoordsBuffer = NULL;
        colorBuffer = NULL;
        numChunkVerts = 0;
        numIndicesForGenerating = 0;
        indexBufferForGenerating = NULL;
        
        /* VBO data is not lock protected and is either exclusively accessed on the main thread
         * or is updated in ways that do not require locking for atomicity.
         */
        vboChunkVerts = 0;
        vboChunkNorms = 0;
        vboChunkTexCoords = 0;
        vboChunkColors = 0;
        numIndicesForDrawing = 0;
        indexBufferForDrawing = NULL;
        needsVBORegeneration = NO;
        
        // Frustum-Box testing requires the corners of the cube, so pre-calculate them here.
        corners[0] = minP;
        corners[1] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GSVector3_Add(minP, GSVector3_Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GSVector3_Add(minP, GSVector3_Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GSVector3_Add(minP, GSVector3_Make(0,            CHUNK_SIZE_Y, 0));
        
        visible = NO;
        
        [self updateWithVoxelData:_chunks doItSynchronously:NO];
    }
    
    return self;
}


- (void)updateWithVoxelData:(GSChunkVoxelData **)_chunks doItSynchronously:(BOOL)sync
{
    assert(_chunks);
    assert(_chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
    assert(_chunks[CHUNK_NEIGHBOR_CENTER]);
    
    GSChunkVoxelData **chunks = copyNeighbors(_chunks);
    
    void (^b)(void) = ^{
        [self generateGeometryWithVoxelData:chunks];
        freeNeighbors(chunks);
    };
    
    if(sync) {
        b();
    } else {
        dispatch_async(chunkTaskQueue, b);
    }
}


// Returns YES if VBOs were generated.
- (BOOL)drawGeneratingVBOsIfNecessary:(BOOL)allowVBOGeneration
{
    BOOL didGenerateVBOs = NO;
    
    BOOL vbosAreMissing = !vboChunkVerts || !vboChunkNorms || !vboChunkTexCoords || !vboChunkColors;
    
    if(needsVBORegeneration || vbosAreMissing) {
        if(allowVBOGeneration) {
            didGenerateVBOs = [self tryToGenerateVBOs];
        } else {
            didGenerateVBOs = NO;
        }
    }
    
    BOOL anyGeometryAtAll = (numIndicesForDrawing>0) && indexBufferForDrawing;
    
    if(anyGeometryAtAll && (didGenerateVBOs || !vbosAreMissing)) {
        glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
        glVertexPointer(3, GL_FLOAT, 0, 0);
        
        glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
        glNormalPointer(GL_FLOAT, 0, 0);
        
        glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
        glTexCoordPointer(3, GL_FLOAT, 0, 0);
        
        glBindBuffer(GL_ARRAY_BUFFER, vboChunkColors);
        glColorPointer(3, GL_FLOAT, 0, 0);
        
        glDrawElements(GL_QUADS, numIndicesForDrawing, GL_UNSIGNED_INT, indexBufferForDrawing);
    }
    
    return didGenerateVBOs;
}


- (void)dealloc
{
    [self destroyVBOs];
    
    [lockGeometry lock];
    [self destroyGeometry];
    [lockGeometry unlockWithCondition:!READY];
    [lockGeometry release];
    
    [glContext release];
    dispatch_release(chunkTaskQueue);
    
    [super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)

// Generates verts, norms, and texCoords buffers from voxel data.
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)chunks
{
    GSVector3 pos;

    assert(chunks);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_CENTER]);
    
    [lockGeometry lock];
    
    [self destroyGeometry];
    
    // Atomically, grab all the voxel data we need to generate geometry for this chunk.
    // We do this atomically to prevent deadlock.
    [[GSChunkStore lockWhileLockingMultipleChunksVoxelData] lock];
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockVoxelData lockForReading];
    }
    [[GSChunkStore lockWhileLockingMultipleChunksVoxelData] unlock];
    
    // Atomically, grab all the sunlight data we need to generate geometry for this chunk.
    // We do this atomically to prevent deadlock.
    [[GSChunkStore lockWhileLockingMultipleChunksSunlight] lock];
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockSunlight lockForReading];
    }
    [[GSChunkStore lockWhileLockingMultipleChunksSunlight] unlock];
    
    // Iterate over all voxels in the chunk and count the number of vertices that would be generated.
    numChunkVerts = 0;
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                numChunkVerts += [self generateGeometryForSingleBlockAtPosition:pos
                                                                    vertsBuffer:NULL
                                                                    normsBuffer:NULL
                                                                texCoordsBuffer:NULL
                                                                    colorBuffer:NULL
                                                                    indexBuffer:NULL
                                                                      voxelData:chunks
                                                              onlyDoingCounting:YES];
                
            }
        }
    }
    assert(numChunkVerts % 4 == 0); // chunk geometry is all done with quads
    
    // Take the vertices array and generate raw buffers for OpenGL to consume.
    vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);
    colorBuffer = allocateGeometryBuffer(numChunkVerts);
    
    GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
    GLfloat *_colorBuffer = colorBuffer;
    GLuint *_indexBufferForGenerating = indexBufferForGenerating;
    
    // Iterate over all voxels in the chunk and generate geometry.
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
                                                   vertsBuffer:&_vertsBuffer
                                                   normsBuffer:&_normsBuffer
                                               texCoordsBuffer:&_texCoordsBuffer
                                                   colorBuffer:&_colorBuffer
                                                   indexBuffer:&_indexBufferForGenerating
                                                     voxelData:chunks
                                             onlyDoingCounting:NO];
                
            }
        }
    }
    
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockSunlight unlockForReading];
    }
    
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockVoxelData unlockForReading];
    }
    
    [self fillIndexBufferForGenerating:numChunkVerts];
    
    // Need to set this flag so VBO rendering code knows that it needs to regenerate from geometry on next redraw.
    // Updating a boolean should be atomic on x86_64 and i386;
    needsVBORegeneration = YES;
    
    [lockGeometry unlockWithCondition:READY];
}


// Assumes the caller is already holding "lockGeometry".
- (void)fillIndexBufferForGenerating:(GLsizei)n
{
    if(indexBufferForGenerating) {
        free(indexBufferForGenerating);
        indexBufferForGenerating = NULL;
    }
    
    numIndicesForGenerating = n;
    
    // Take the indices array and generate a raw index buffer that OpenGL can consume.
    indexBufferForGenerating = malloc(sizeof(GLuint) * numIndicesForGenerating);
    if(!indexBufferForGenerating) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
    }
    
    for(GLsizei i = 0; i < numIndicesForGenerating; ++i)
    {
        indexBufferForGenerating[i] = i; // a simple linear walk
    }
}


// Assumes the caller is already holding "lockGeometry".
- (void)destroyGeometry
{
    free(vertsBuffer);
    vertsBuffer = NULL;
    
    free(normsBuffer);
    normsBuffer = NULL;
    
    free(texCoordsBuffer);
    texCoordsBuffer = NULL;
    
    free(colorBuffer);
    colorBuffer = NULL;
    
    free(indexBufferForGenerating);
    indexBufferForGenerating = NULL;
    
    numChunkVerts = 0;
    numIndicesForGenerating = 0;
}


- (void)countNeighborsForAmbientOcclusionsAtPoint:(GSIntegerVector3)p
                                        neighbors:(GSChunkVoxelData **)chunks
                              outAmbientOcclusion:(block_lighting_t*)ao
{
    /* Front is in the -Z direction and back is the +Z direction.
     * This is a totally arbitrary convention.
     */
    
#define OCCLUSION(x, y, z) (occlusion[(x+1)*3*3 + (y+1)*3 + (z+1)])
    
    BOOL occlusion[3*3*3];
    
    for(ssize_t x = -1; x <= 1; ++x)
    {
        for(ssize_t y = -1; y <= 1; ++y)
        {
            for(ssize_t z = -1; z <= 1; ++z)
            {
                OCCLUSION(x, y, z) = isEmptyAtPoint(GSIntegerVector3_Make(p.x + x, p.y + y, p.z + z), chunks);
            }
        }
    }
    
    ao->top = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION( 0, 1,  0),
                                                                  OCCLUSION( 0, 1, -1),
                                                                  OCCLUSION(-1, 1,  0),
                                                                  OCCLUSION(-1, 1, -1)),
                                               calcFinalOcclusion(OCCLUSION( 0, 1,  0),
                                                                  OCCLUSION( 0, 1, +1),
                                                                  OCCLUSION(-1, 1,  0),
                                                                  OCCLUSION(-1, 1, +1)),
                                               calcFinalOcclusion(OCCLUSION( 0, 1,  0),
                                                                  OCCLUSION( 0, 1, +1),
                                                                  OCCLUSION(+1, 1,  0),
                                                                  OCCLUSION(+1, 1, +1)),
                                               calcFinalOcclusion(OCCLUSION( 0, 1,  0),
                                                                  OCCLUSION( 0, 1, -1),
                                                                  OCCLUSION(+1, 1,  0),
                                                                  OCCLUSION(+1, 1, -1)));
    
    ao->bottom = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION( 0, -1,  0),
                                                                     OCCLUSION( 0, -1, -1),
                                                                     OCCLUSION(-1, -1,  0),
                                                                     OCCLUSION(-1, -1, -1)),
                                                  calcFinalOcclusion(OCCLUSION( 0, -1,  0),
                                                                     OCCLUSION( 0, -1, -1),
                                                                     OCCLUSION(+1, -1,  0),
                                                                     OCCLUSION(+1, -1, -1)),
                                                  calcFinalOcclusion(OCCLUSION( 0, -1,  0),
                                                                     OCCLUSION( 0, -1, +1),
                                                                     OCCLUSION(+1, -1,  0),
                                                                     OCCLUSION(+1, -1, +1)),
                                                  calcFinalOcclusion(OCCLUSION( 0, -1,  0),
                                                                     OCCLUSION( 0, -1, +1),
                                                                     OCCLUSION(-1, -1,  0),
                                                                     OCCLUSION(-1, -1, +1)));
    
    ao->back = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION( 0, -1, 1),
                                                                   OCCLUSION( 0,  0, 1),
                                                                   OCCLUSION(-1, -1, 1),
                                                                   OCCLUSION(-1,  0, 1)),
                                                calcFinalOcclusion(OCCLUSION( 0, -1, 1),
                                                                   OCCLUSION( 0,  0, 1),
                                                                   OCCLUSION(+1, -1, 1),
                                                                   OCCLUSION(+1,  0, 1)),
                                                calcFinalOcclusion(OCCLUSION( 0, +1, 1),
                                                                   OCCLUSION( 0,  0, 1),
                                                                   OCCLUSION(+1, +1, 1),
                                                                   OCCLUSION(+1,  0, 1)),
                                                calcFinalOcclusion(OCCLUSION( 0, +1, 1),
                                                                   OCCLUSION( 0,  0, 1),
                                                                   OCCLUSION(-1, +1, 1),
                                                                   OCCLUSION(-1,  0, 1)));
    
    ao->front = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION( 0, -1, -1),
                                                                    OCCLUSION( 0,  0, -1),
                                                                    OCCLUSION(-1, -1, -1),
                                                                    OCCLUSION(-1,  0, -1)),
                                                 calcFinalOcclusion(OCCLUSION( 0, +1, -1),
                                                                    OCCLUSION( 0,  0, -1),
                                                                    OCCLUSION(-1, +1, -1),
                                                                    OCCLUSION(-1,  0, -1)),
                                                 calcFinalOcclusion(OCCLUSION( 0, +1, -1),
                                                                    OCCLUSION( 0,  0, -1),
                                                                    OCCLUSION(+1, +1, -1),
                                                                    OCCLUSION(+1,  0, -1)),
                                                 calcFinalOcclusion(OCCLUSION( 0, -1, -1),
                                                                    OCCLUSION( 0,  0, -1),
                                                                    OCCLUSION(+1, -1, -1),
                                                                    OCCLUSION(+1,  0, -1)));
    
    ao->right = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION(+1,  0,  0),
                                                                    OCCLUSION(+1,  0, -1),
                                                                    OCCLUSION(+1, -1,  0),
                                                                    OCCLUSION(+1, -1, -1)),
                                                 calcFinalOcclusion(OCCLUSION(+1,  0,  0),
                                                                    OCCLUSION(+1,  0, -1),
                                                                    OCCLUSION(+1, +1,  0),
                                                                    OCCLUSION(+1, +1, -1)),
                                                 calcFinalOcclusion(OCCLUSION(+1,  0,  0),
                                                                    OCCLUSION(+1,  0, +1),
                                                                    OCCLUSION(+1, +1,  0),
                                                                    OCCLUSION(+1, +1, +1)),
                                                 calcFinalOcclusion(OCCLUSION(+1,  0,  0),
                                                                    OCCLUSION(+1,  0, +1),
                                                                    OCCLUSION(+1, -1,  0),
                                                                    OCCLUSION(+1, -1, +1)));
    
    ao->left = packBlockLightingValuesForVertex(calcFinalOcclusion(OCCLUSION(-1,  0,  0),
                                                                   OCCLUSION(-1,  0, -1),
                                                                   OCCLUSION(-1, -1,  0),
                                                                   OCCLUSION(-1, -1, -1)),
                                                calcFinalOcclusion(OCCLUSION(-1,  0,  0),
                                                                   OCCLUSION(-1,  0, +1),
                                                                   OCCLUSION(-1, -1,  0),
                                                                   OCCLUSION(-1, -1, +1)),
                                                calcFinalOcclusion(OCCLUSION(-1,  0,  0),
                                                                   OCCLUSION(-1,  0, +1),
                                                                   OCCLUSION(-1, +1,  0),
                                                                   OCCLUSION(-1, +1, +1)),
                                                calcFinalOcclusion(OCCLUSION(-1,  0,  0),
                                                                   OCCLUSION(-1,  0, -1),
                                                                   OCCLUSION(-1, +1,  0),
                                                                   OCCLUSION(-1, +1, -1)));
}


/* Assumes the caller is already holding "lockGeometry", "lockSunlight", "lockAmbientOcclusion",
 * and locks on all neighboring chunks too.
 */
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertsBuffer:(GLfloat **)_vertsBuffer
                                        normsBuffer:(GLfloat **)_normsBuffer
                                    texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                        colorBuffer:(GLfloat **)_colorBuffer
                                        indexBuffer:(GLuint **)_indexBuffer
                                          voxelData:(GSChunkVoxelData **)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting
{
    assert(chunks);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_ZER_Z]);
    assert(chunks[CHUNK_NEIGHBOR_POS_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_ZER_Z]);
    assert(chunks[CHUNK_NEIGHBOR_NEG_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_ZER_X_NEG_Z]);
    assert(chunks[CHUNK_NEIGHBOR_ZER_X_POS_Z]);
    assert(chunks[CHUNK_NEIGHBOR_CENTER]);
    
    if(!onlyDoingCounting && !(_vertsBuffer && _normsBuffer && _texCoordsBuffer && _colorBuffer && _indexBuffer)) {
        [NSException raise:NSInvalidArgumentException format:@"If countOnly is NO then pointers to buffers must be provided."];
    }
    
    GLsizei count = 0;

    const GLfloat L = 0.5f; // half the length of a block along one side
    const GLfloat grass = 0;
    const GLfloat dirt = 1;
    const GLfloat side = 2;
    GLfloat page = dirt;
    
    GLfloat x = pos.x;
    GLfloat y = pos.y;
    GLfloat z = pos.z;
    
    GLfloat minX = minP.x;
    GLfloat minY = minP.y;
    GLfloat minZ = minP.z;
    
    GSIntegerVector3 chunkLocalPos = {x-minX, y-minY, z-minZ};
    
    GSChunkVoxelData *voxels = chunks[CHUNK_NEIGHBOR_CENTER];
    
    voxel_t *thisVoxel = [voxels getPointerToVoxelAtPoint:chunkLocalPos];
    
    if(isVoxelEmpty(*thisVoxel)) {
        return count;
    }
    
    const float torchLight = 0.0; // TODO: add torch lighting to the world.
    
    block_lighting_t ambientOcclusion;
    if(!onlyDoingCounting) {
        [self countNeighborsForAmbientOcclusionsAtPoint:chunkLocalPos
                                              neighbors:chunks
                                    outAmbientOcclusion:&ambientOcclusion];
    }
    
    block_lighting_t sunlight;
    [chunks[CHUNK_NEIGHBOR_CENTER] getSunlightAtPoint:chunkLocalPos
                                            neighbors:chunks
                                          outLighting:&sunlight];
    
    unsigned unpackedSunlight[4];
    unsigned unpackedAO[4];
    
    // Top Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY+1, z-minZ), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            page = side;
            
            unpackBlockLightingValuesForVertex(sunlight.top, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.top, unpackedAO);
            
            addVertex(x-L, y+L, z-L,
                      0, 1, 0,
                      1, 0, grass,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y+L, z+L,
                      0, 1, 0,
                      1, 1, grass,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z+L,
                      0, 1, 0,
                      0, 1, grass,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z-L,
                      0, 1, 0,
                      0, 0, grass,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    // Bottom Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY-1, z-minZ), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            unpackBlockLightingValuesForVertex(sunlight.bottom, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.bottom, unpackedAO);
            
            addVertex(x-L, y-L, z-L,
                      0, -1, 0,
                      1, 0, dirt,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y-L, z-L,
                      0, -1, 0,
                      0, 0, dirt,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y-L, z+L,
                      0, -1, 0,
                      0, 1, dirt,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y-L, z+L,
                      0, -1, 0,
                      1, 1, dirt,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    // Back Face (+Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ+1), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            unpackBlockLightingValuesForVertex(sunlight.back, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.back, unpackedAO);
            
            addVertex(x-L, y-L, z+L,
                      0, 0, 1,
                      0, 1, page,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y-L, z+L,
                      0, 0, 1,
                      1, 1, page,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z+L,
                      0, 0, 1,
                      1, 0, page,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y+L, z+L,
                      0, 0, 1,
                      0, 0, page,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    // Front Face (-Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ-1), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            unpackBlockLightingValuesForVertex(sunlight.front, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.front, unpackedAO);
            
            addVertex(x-L, y-L, z-L,
                      0, 1, -1,
                      0, 1, page,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y+L, z-L,
                      0, 1, -1,
                      0, 0, page,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z-L,
                      0, 1, -1,
                      1, 0, page,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y-L, z-L,
                      0, 1, -1,
                      1, 1, page,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    // Right Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX+1, y-minY, z-minZ), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            unpackBlockLightingValuesForVertex(sunlight.right, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.right, unpackedAO);
            
            addVertex(x+L, y-L, z-L,
                      1, 0, 0,
                      0, 1, page,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z-L,
                      1, 0, 0,
                      0, 0, page,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y+L, z+L,
                      1, 0, 0,
                      1, 0, page,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x+L, y-L, z+L,
                      1, 0, 0,
                      1, 1, page,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    // Left Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX-1, y-minY, z-minZ), chunks)) {
        count += 4;
        
        if(!onlyDoingCounting) {
            unpackBlockLightingValuesForVertex(sunlight.left, unpackedSunlight);
            unpackBlockLightingValuesForVertex(ambientOcclusion.left, unpackedAO);
            
            addVertex(x-L, y-L, z-L,
                      -1, 0, 0,
                      0, 1, page,
                      blockLight(unpackedSunlight[0], torchLight, unpackedAO[0]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y-L, z+L,
                      -1, 0, 0,
                      1, 1, page,
                      blockLight(unpackedSunlight[1], torchLight, unpackedAO[1]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y+L, z+L,
                      -1, 0, 0,
                      1, 0, page,
                      blockLight(unpackedSunlight[2], torchLight, unpackedAO[2]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
            
            addVertex(x-L, y+L, z-L,
                      -1, 0, 0,
                      0, 0, page,
                      blockLight(unpackedSunlight[3], torchLight, unpackedAO[3]),
                      _vertsBuffer,
                      _normsBuffer,
                      _texCoordsBuffer,
                      _colorBuffer);
        }
    }
    
    return count;
}


- (BOOL)tryToGenerateVBOs
{
    if(![lockGeometry tryLockWhenCondition:READY]) {
        return NO;
    }
    
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();
    [self destroyVBOs];
    
    GLsizei len = 3 * numChunkVerts * sizeof(GLfloat);
    
    glGenBuffers(1, &vboChunkVerts);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkVerts);
    glBufferData(GL_ARRAY_BUFFER, len, vertsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkNorms);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkNorms);
    glBufferData(GL_ARRAY_BUFFER, len, normsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkTexCoords);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkTexCoords);
    glBufferData(GL_ARRAY_BUFFER, len, texCoordsBuffer, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vboChunkColors);
    glBindBuffer(GL_ARRAY_BUFFER, vboChunkColors);
    glBufferData(GL_ARRAY_BUFFER, len, colorBuffer, GL_STATIC_DRAW);
    
    // Simply quickly swap the index buffers to get the index buffer to use for actual drawing.
    SWAP(indexBufferForDrawing, indexBufferForGenerating);
    SWAP(numIndicesForDrawing, numIndicesForGenerating);
    
    needsVBORegeneration = NO; // reset
    
    // Geometry isn't needed anymore, so free it now.
    [self destroyGeometry];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk VBOs. It took %.3fs.", timeEnd - timeStart);
    [lockGeometry unlock];
    
    return YES;
}


- (void)destroyVBOs
{
    asyncDestroyChunkVBOs(glContext, vboChunkVerts, vboChunkNorms, vboChunkTexCoords, vboChunkColors);
    
    vboChunkVerts = 0;
    vboChunkNorms = 0;
    vboChunkTexCoords = 0;
    vboChunkColors = 0;
    
    numIndicesForDrawing = 0;
    free(indexBufferForDrawing);
    indexBufferForDrawing = NULL;
}

@end


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo)
{
    [context makeCurrentContext];
    CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
    glDeleteBuffers(1, &vbo);
    CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
}


static void asyncDestroyChunkVBOs(NSOpenGLContext *context,
                                  GLuint vboChunkVerts,
                                  GLuint vboChunkNorms,
                                  GLuint vboChunkTexCoords,
                                  GLuint vboChunkColors)
{
    // Free the VBOs on the main thread. Doesn't have to be synchronous with the dealloc method, though.
    
    if(vboChunkVerts) {
        dispatch_async(dispatch_get_main_queue(), ^{
            syncDestroySingleVBO(context, vboChunkVerts);
        });
    }
    
    if(vboChunkNorms) {
        dispatch_async(dispatch_get_main_queue(), ^{
            syncDestroySingleVBO(context, vboChunkNorms);
        });
    }
    
    if(vboChunkTexCoords) {
        dispatch_async(dispatch_get_main_queue(), ^{
            syncDestroySingleVBO(context, vboChunkTexCoords);
        });
    }
    
    if(vboChunkColors) {
        dispatch_async(dispatch_get_main_queue(), ^{
            syncDestroySingleVBO(context, vboChunkColors);
        });
    }
}


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GSVector3 c,
                      GLfloat **verts,
                      GLfloat **norms,
                      GLfloat **txcds,
                      GLfloat **color)
{
    **verts = vx; (*verts)++;
    **verts = vy; (*verts)++;
    **verts = vz; (*verts)++;
    
    **norms = nx; (*norms)++;
    **norms = ny; (*norms)++;
    **norms = nz; (*norms)++;
    
    **txcds = tx; (*txcds)++;
    **txcds = ty; (*txcds)++;
    **txcds = tz; (*txcds)++;
    
    **color = c.x; (*color)++;
    **color = c.y; (*color)++;
    **color = c.z; (*color)++;
}


// Allocate a buffer for use in geometry generation.
static GLfloat * allocateGeometryBuffer(size_t numVerts)
{
    GLfloat *buffer = malloc(sizeof(GLfloat) * 3 * numVerts);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    
    return buffer;
}
