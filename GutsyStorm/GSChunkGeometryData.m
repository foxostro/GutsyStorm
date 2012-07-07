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


static void destroyChunkVBOs(GLuint vboChunkVerts, GLuint vboChunkNorms, GLuint vboChunkTexCoords, GLuint vboChunkColors);

static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GSVector3  color,
                      NSMutableArray *vertices,
                      NSMutableArray *indices);

static GLfloat * allocateGeometryBuffer(size_t numVerts);


static inline GSVector3 blockLight(uint8_t sunlight, uint8_t torchLight, uint8_t ambientOcclusion)
{
    // Pack ambient occlusion into the Red channel, sunlight into the Green channel, and torch light into the Blue channel.
    return GSVector3_Make(ambientOcclusion / 255.0f, sunlight / 255.0f, torchLight / 255.0f);
}


@interface GSChunkGeometryData (Private)

- (BOOL)tryToGenerateVBOs;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)voxels;
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertices:(NSMutableArray *)vertices
                                         indices:(NSMutableArray *)indices
                                       voxelData:(GSChunkVoxelData **)voxels;
- (void)fillIndexBufferForGenerating:(NSMutableArray *)indices;

@end


@implementation GSChunkGeometryData


- (id)initWithMinP:(GSVector3)_minP
         voxelData:(GSChunkVoxelData **)_chunks
{
    self = [super initWithMinP:_minP];
    if (self) {
        // Initialization code here.
        
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
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        dispatch_sync(queue, b);
    } else {
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_async(queue, b);
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
    
    [super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)

// Generates verts, norms, and texCoords buffers from voxel data.
- (void)generateGeometryWithVoxelData:(GSChunkVoxelData **)chunks
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
    
    GSVector3 pos;
    
    [lockGeometry lock];
    
    [self destroyGeometry];
    
    NSMutableArray *vertices = [[NSMutableArray alloc] init];
    NSMutableArray *indices = [[NSMutableArray alloc] init];
    
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
    
    [chunks[CHUNK_NEIGHBOR_CENTER]->lockAmbientOcclusion lockWhenCondition:READY];
    
    // Iterate over all voxels in the chunk and generate geometry.
    for(pos.x = minP.x; pos.x < maxP.x; ++pos.x)
    {
        for(pos.y = minP.y; pos.y < maxP.y; ++pos.y)
        {
            for(pos.z = minP.z; pos.z < maxP.z; ++pos.z)
            {
                [self generateGeometryForSingleBlockAtPosition:pos
                                                      vertices:vertices
                                                       indices:indices
                                                     voxelData:chunks];
                
            }
        }
    }
    
    [chunks[CHUNK_NEIGHBOR_CENTER]->lockAmbientOcclusion unlockWithCondition:READY];
    
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockSunlight unlockForReading];
    }
    
    for(size_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        [chunks[i]->lockVoxelData unlockForReading];
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    numChunkVerts = (GLsizei)[vertices count];
    
    // Take the vertices array and generate raw buffers for OpenGL to consume.
    vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);
    colorBuffer = allocateGeometryBuffer(numChunkVerts);
    
    GLfloat *_vertsBuffer = vertsBuffer;
    GLfloat *_normsBuffer = normsBuffer;
    GLfloat *_texCoordsBuffer = texCoordsBuffer;
    GLfloat *_colorBuffer = colorBuffer;
    for(GSVertex *vertex in vertices)
    {
        GSVector3 v = [vertex.position getVector];
        GSVector3 n = [vertex.normal getVector];
        GSVector3 t = [vertex.texCoord getVector];
        GSVector3 c = [vertex.color getVector];
        
        _vertsBuffer[0] = v.x;
        _vertsBuffer[1] = v.y;
        _vertsBuffer[2] = v.z;
        _vertsBuffer += 3;
        
        _normsBuffer[0] = n.x;
        _normsBuffer[1] = n.y;
        _normsBuffer[2] = n.z;
        _normsBuffer += 3;
        
        _texCoordsBuffer[0] = t.x;
        _texCoordsBuffer[1] = t.y;
        _texCoordsBuffer[2] = t.z;
        _texCoordsBuffer += 3;
        
        _colorBuffer[0] = c.x;
        _colorBuffer[1] = c.y;
        _colorBuffer[2] = c.z;
        _colorBuffer += 3;
    }
    
    [vertices release];
    
    [self fillIndexBufferForGenerating:indices];
    [indices release];
    
    // Need to set this flag so VBO rendering code knows that it needs to regenerate from geometry on next redraw.
    // Updating a boolean should be atomic on x86_64 and i386;
    needsVBORegeneration = YES;
    
    [lockGeometry unlockWithCondition:READY];
}


// Assumes the caller is already holding "lockGeometry".
- (void)fillIndexBufferForGenerating:(NSMutableArray *)indices
{
    if(indexBufferForGenerating) {
        free(indexBufferForGenerating);
        indexBufferForGenerating = NULL;
    }
    
    numIndicesForGenerating = (GLsizei)[indices count];
    
    // Take the indices array and generate a raw index buffer that OpenGL can consume.
    indexBufferForGenerating = malloc(sizeof(GLuint) * numIndicesForGenerating);
    if(!indexBufferForGenerating) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
    }
    
    for(GLsizei i = 0; i < numIndicesForGenerating; ++i)
    {
        indexBufferForGenerating[i] = [[indices objectAtIndex:i] unsignedIntValue];
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


/* Assumes the caller is already holding "lockGeometry", "lockSunlight", "lockAmbientOcclusion",
 * and locks on all neighboring chunks too.
 */
- (void)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertices:(NSMutableArray *)vertices
                                         indices:(NSMutableArray *)indices
                                       voxelData:(GSChunkVoxelData **)chunks
{
    assert(vertices);
    assert(indices);
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
        return;
    }
    
    const float torchLight = 0.0; // TODO: add torch lighting to the world.
    
    block_lighting_t ambientOcclusion = [chunks[CHUNK_NEIGHBOR_CENTER] getAmbientOcclusionAtPoint:chunkLocalPos];
    
    block_lighting_t sunlight;
    [chunks[CHUNK_NEIGHBOR_CENTER] getSunlightAtPoint:chunkLocalPos
                                            neighbors:chunks
                                          outLighting:&sunlight];
    
    // Top Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY+1, z-minZ), chunks)) {
        page = side;
        
        addVertex(x-L, y+L, z-L,
                  0, 1, 0,
                  1, 0, grass,
                  blockLight(sunlight.top[0], torchLight, ambientOcclusion.top[0]),
                  vertices,
                  indices);
        
        addVertex(x-L, y+L, z+L,
                  0, 1, 0,
                  1, 1, grass,
                  blockLight(sunlight.top[1], torchLight, ambientOcclusion.top[1]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z+L,
                  0, 1, 0,
                  0, 1, grass,
                  blockLight(sunlight.top[2], torchLight, ambientOcclusion.top[2]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z-L,
                  0, 1, 0,
                  0, 0, grass,
                  blockLight(sunlight.top[3], torchLight, ambientOcclusion.top[3]),
                  vertices,
                  indices);
    }
    
    // Bottom Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY-1, z-minZ), chunks)) {
        addVertex(x-L, y-L, z-L,
                  0, -1, 0,
                  1, 0, dirt,
                  blockLight(sunlight.bottom[0], torchLight, ambientOcclusion.bottom[0]),
                  vertices,
                  indices);
        
        addVertex(x+L, y-L, z-L,
                  0, -1, 0,
                  0, 0, dirt,
                  blockLight(sunlight.bottom[1], torchLight, ambientOcclusion.bottom[1]),
                  vertices,
                  indices);
        
        addVertex(x+L, y-L, z+L,
                  0, -1, 0,
                  0, 1, dirt,
                  blockLight(sunlight.bottom[2], torchLight, ambientOcclusion.bottom[2]),
                  vertices,
                  indices);
        
        addVertex(x-L, y-L, z+L,
                  0, -1, 0,
                  1, 1, dirt,
                  blockLight(sunlight.bottom[3], torchLight, ambientOcclusion.bottom[3]),
                  vertices,
                  indices);
    }
    
    // Back Face (+Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ+1), chunks)) {
        addVertex(x-L, y-L, z+L,
                  0, 0, 1,
                  0, 1, page,
                  blockLight(sunlight.back[0], torchLight, ambientOcclusion.back[0]),
                  vertices,
                  indices);
        
        addVertex(x+L, y-L, z+L,
                  0, 0, 1,
                  1, 1, page,
                  blockLight(sunlight.back[1], torchLight, ambientOcclusion.back[1]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z+L,
                  0, 0, 1,
                  1, 0, page,
                  blockLight(sunlight.back[2], torchLight, ambientOcclusion.back[2]),
                  vertices,
                  indices);
        
        addVertex(x-L, y+L, z+L,
                  0, 0, 1,
                  0, 0, page,
                  blockLight(sunlight.back[3], torchLight, ambientOcclusion.back[3]),
                  vertices,
                  indices);
    }
    
    // Front Face (-Z)
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX, y-minY, z-minZ-1), chunks)) {
        addVertex(x-L, y-L, z-L,
                  0, 1, -1,
                  0, 1, page,
                  blockLight(sunlight.front[0], torchLight, ambientOcclusion.front[0]),
                  vertices,
                  indices);
        
        addVertex(x-L, y+L, z-L,
                  0, 1, -1,
                  0, 0, page,
                  blockLight(sunlight.front[1], torchLight, ambientOcclusion.front[1]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z-L,
                  0, 1, -1,
                  1, 0, page,
                  blockLight(sunlight.front[2], torchLight, ambientOcclusion.front[2]),
                  vertices,
                  indices);
        
        addVertex(x+L, y-L, z-L,
                  0, 1, -1,
                  1, 1, page,
                  blockLight(sunlight.front[3], torchLight, ambientOcclusion.front[3]),
                  vertices,
                  indices);
    }
    
    // Right Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX+1, y-minY, z-minZ), chunks)) {
        addVertex(x+L, y-L, z-L,
                  1, 0, 0,
                  0, 1, page,
                  blockLight(sunlight.right[0], torchLight, ambientOcclusion.right[0]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z-L,
                  1, 0, 0,
                  0, 0, page,
                  blockLight(sunlight.right[1], torchLight, ambientOcclusion.right[1]),
                  vertices,
                  indices);
        
        addVertex(x+L, y+L, z+L,
                  1, 0, 0,
                  1, 0, page,
                  blockLight(sunlight.right[2], torchLight, ambientOcclusion.right[2]),
                  vertices,
                  indices);
        
        addVertex(x+L, y-L, z+L,
                  1, 0, 0,
                  1, 1, page,
                  blockLight(sunlight.right[3], torchLight, ambientOcclusion.right[3]),
                  vertices,
                  indices);
    }
    
    // Left Face
    if(isEmptyAtPoint(GSIntegerVector3_Make(x-minX-1, y-minY, z-minZ), chunks)) {
        addVertex(x-L, y-L, z-L,
                  -1, 0, 0,
                  0, 1, page,
                  blockLight(sunlight.left[0], torchLight, ambientOcclusion.left[0]),
                  vertices,
                  indices);
        
        addVertex(x-L, y-L, z+L,
                  -1, 0, 0,
                  1, 1, page,
                  blockLight(sunlight.left[1], torchLight, ambientOcclusion.left[1]),
                  vertices,
                  indices);
        
        addVertex(x-L, y+L, z+L,
                  -1, 0, 0,
                  1, 0, page,
                  blockLight(sunlight.left[2], torchLight, ambientOcclusion.left[2]),
                  vertices,
                  indices);
        
        addVertex(x-L, y+L, z-L,
                  -1, 0, 0,
                  0, 0, page,
                  blockLight(sunlight.left[3], torchLight, ambientOcclusion.left[3]),
                  vertices,
                  indices);
    }
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
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished generating chunk VBOs. It took %.3fs.", timeEnd - timeStart);
    [lockGeometry unlock];
    
    return YES;
}


- (void)destroyVBOs
{
    destroyChunkVBOs(vboChunkVerts, vboChunkNorms, vboChunkTexCoords, vboChunkColors);
    
    vboChunkVerts = 0;
    vboChunkNorms = 0;
    vboChunkTexCoords = 0;
    vboChunkColors = 0;
    
    numIndicesForDrawing = 0;
    free(indexBufferForDrawing);
    indexBufferForDrawing = NULL;
}

@end


static void destroyChunkVBOs(GLuint vboChunkVerts, GLuint vboChunkNorms, GLuint vboChunkTexCoords, GLuint vboChunkColors)
{
    // Free the VBOs on the main thread. Doesn't have to be synchronous with this dealloc method, though.
    dispatch_async(dispatch_get_main_queue(), ^{
        if(vboChunkVerts && glIsBuffer(vboChunkVerts)) {
            glDeleteBuffers(1, &vboChunkVerts);
        }
        
        if(vboChunkNorms && glIsBuffer(vboChunkNorms)) {
            glDeleteBuffers(1, &vboChunkNorms);
        }
        
        if(vboChunkTexCoords && glIsBuffer(vboChunkTexCoords)) {
            glDeleteBuffers(1, &vboChunkTexCoords);
        }
        
        if(vboChunkColors && glIsBuffer(vboChunkColors)) {
            glDeleteBuffers(1, &vboChunkColors);
        }
    });
}


static void addVertex(GLfloat vx, GLfloat vy, GLfloat vz,
                      GLfloat nx, GLfloat ny, GLfloat nz,
                      GLfloat tx, GLfloat ty, GLfloat tz,
                      GSVector3 c,
                      NSMutableArray *vertices,
                      NSMutableArray *indices)
{
    GSBoxedVector *position = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(vx, vy, vz)] autorelease];
    GSBoxedVector *normal   = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(nx, ny, nz)] autorelease];
    GSBoxedVector *texCoord = [[[GSBoxedVector alloc] initWithVector:GSVector3_Make(tx, ty, tz)] autorelease];
    GSBoxedVector *color = [[[GSBoxedVector alloc] initWithVector:c] autorelease];
    
    GSVertex *vertex = [[[GSVertex alloc] initWithPosition:position
                                                    normal:normal
                                                  texCoord:texCoord
                                                     color:color] autorelease];
    
    [vertices addObject:vertex];
    [indices addObject:[NSNumber numberWithUnsignedInteger:[vertices count]-1]];
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
