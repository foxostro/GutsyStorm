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


static inline GSVector3 blockLight(unsigned sunlight, unsigned torchLight)
{
    // Pack sunlight into the Green channel, and torch light into the Blue channel.
    return GSVector3_Make(0,
                          (sunlight / (float)CHUNK_LIGHTING_MAX) * 0.8f + 0.2f,
                          torchLight / (float)CHUNK_LIGHTING_MAX);
}


const static GLfloat L = 0.5f; // half the length of a block along one side
const static int grass = 0;
const static int dirt = 1;
const static int side = 2;

const static GSIntegerVector3 test[FACE_NUM_FACES] = {
    {0, +1, 0},
    {0, -1, 0},
    {0, 0, +1},
    {0, 0, -1},
    {+1, 0, 0},
    {-1, 0, 0}
};

const static GSVector3 normals[FACE_NUM_FACES] = {
    {0, 1, 0},
    {0, -1, 0},
    {0, 0, 1},
    {0, 1, -1},
    {1, 0, 0},
    {-1, 0, 0},
};

const static GSVector3 vertex[4][FACE_NUM_FACES] = {
    {
        {-L, +L, -L},
        {-L, -L, -L},
        {-L, -L, +L},
        {-L, -L, -L},
        {+L, -L, -L},
        {-L, -L, -L}
    },
    {
        {-L, +L, +L},
        {+L, -L, -L},
        {+L, -L, +L},
        {-L, +L, -L},
        {+L, +L, -L},
        {-L, -L, +L}
    },
    {
        {+L, +L, +L},
        {+L, -L, +L},
        {+L, +L, +L},
        {+L, +L, -L},
        {+L, +L, +L},
        {-L, +L, +L}
    },
    {
        {+L, +L, -L},
        {-L, -L, +L},
        {-L, +L, +L},
        {+L, -L, -L},
        {+L, -L, +L},
        {-L, +L, -L}
    }
};

const static GSIntegerVector3 texCoord[4][FACE_NUM_FACES] = {
    {
        {1, 0, grass},
        {1, 0, dirt},
        {0, 1, -1},
        {0, 1, -1},
        {0, 1, -1},
        {0, 1, -1}
    },
    {
        {1, 1, grass},
        {0, 0, dirt},
        {1, 1, -1},
        {0, 0, -1},
        {0, 0, -1},
        {1, 1, -1}
    },
    {
        {0, 1, grass},
        {0, 1, dirt},
        {1, 0, -1},
        {1, 0, -1},
        {1, 0, -1},
        {1, 0, -1}
    },
    {
        {0, 0, grass},
        {1, 1, dirt},
        {0, 0, -1},
        {1, 1, -1},
        {1, 1, -1},
        {0, 0, -1}
    },
};


@interface GSChunkGeometryData (Private)

- (BOOL)tryToGenerateVBOs;
- (void)destroyVBOs;
- (void)destroyGeometry;
- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)chunks;
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertsBuffer:(GLfloat **)_vertsBuffer
                                        normsBuffer:(GLfloat **)_normsBuffer
                                    texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                        colorBuffer:(GLfloat **)_colorBuffer
                                        indexBuffer:(GLuint **)_indexBuffer
                                          voxelData:(GSNeighborhood *)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting;
- (void)fillIndexBufferForGenerating:(GLsizei)n;
- (NSData *)dataRepr;
- (void)saveGeometryDataToFile;
- (void)fillGeometryBuffersUsingDataRepr:(NSData *)data;
- (BOOL)tryToLoadGeometryFromFile;

@end


@implementation GSChunkGeometryData

@synthesize dirty;


+ (NSString *)fileNameForGeometryDataFromMinP:(GSVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.geometry.dat", minP.x, minP.y, minP.z];
}


- (id)initWithMinP:(GSVector3)_minP
            folder:(NSURL *)_folder
    groupForSaving:(dispatch_group_t)_groupForSaving
    chunkTaskQueue:(dispatch_queue_t)chunkTaskQueue
         glContext:(NSOpenGLContext *)_glContext
{
    self = [super initWithMinP:_minP];
    if (self) {
        glContext = _glContext;
        [glContext retain];
        
        folder = _folder;
        [folder retain];
        
        groupForSaving = _groupForSaving;
        dispatch_retain(groupForSaving);
        
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
        dirty = YES;
        updateInFlight = 0;
        
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
        
        // Try to load geometry from file so we have something to show before regeneration finishes.
        dispatch_async(chunkTaskQueue, ^{
            [self tryToLoadGeometryFromFile];
        });
    }
    
    return self;
}


- (BOOL)tryToUpdateWithVoxelData:(GSNeighborhood *)neighborhood
{
    __block BOOL success = NO;
    
    if(!OSAtomicCompareAndSwapIntBarrier(0, 1, &updateInFlight)) {
        DebugLog(@"Can't update geometry: already in-flight.");
        return NO; // an update is already in flight, so bail out now
    }
    
    void (^b)(void) = ^{
        __block BOOL anyNeighborHasDirtySunlight = NO;
        [neighborhood enumerateNeighborsWithBlock:^(GSChunkVoxelData *voxels) {
            if(voxels.dirtySunlight) {
                anyNeighborHasDirtySunlight = YES;
            }
        }];
        
        if(anyNeighborHasDirtySunlight) {
            OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
            DebugLog(@"Can't update geometry: a neighbor has dirty sunlight data.");
            return;
        }
        
        if(![lockGeometry tryLock]) {
            OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
            DebugLog(@"Can't update geometry: lockGeometry is already taken.");
            return;
        }
        
        GSChunkVoxelData *center = [neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
        
        if([center.sunlight.lockLightingBuffer tryLockForReading]) {
            [self destroyGeometry];
            [self fillGeometryBuffersUsingVoxelData:neighborhood];
            [center.sunlight.lockLightingBuffer unlockForReading];
            
            [self fillIndexBufferForGenerating:numChunkVerts];
            
            // Need to set this flag so VBO rendering code knows that it needs to regenerate from geometry on next redraw.
            // Updating a boolean should be atomic on x86_64 and i386;
            needsVBORegeneration = YES;
            
            // Cache geometry buffers on disk for next time.
            dispatch_group_async(groupForSaving, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self saveGeometryDataToFile];
            });
            
            dirty = NO;
            OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
            [lockGeometry unlockWithCondition:READY];
            success = YES;
        } else {
            OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
            [lockGeometry unlockWithCondition:!READY];
            DebugLog(@"Can't update geometry: sunlight buffer is busy.");
        }
    };
    
    if(![neighborhood tryReaderAccessToVoxelDataUsingBlock:b]) {
        OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
        DebugLog(@"Can't update geometry: voxel data buffers are busy.");
    }
    
    return success;
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
    [self destroyGeometry];
    [lockGeometry release];
    [glContext release];
    [folder release];
    dispatch_release(groupForSaving);
    [super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)

/* Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight.lockLightingBuffer" for the center chunk in the neighborhood (for reading).
 */
- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)chunks
{
    GSVector3 pos;
    
    // Iterate over all voxels in the chunk and count the number of vertices that would be generated.
    numChunkVerts = 0;
    FOR_BOX(pos, minP, maxP)
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
    FOR_BOX(pos, minP, maxP)
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


/* Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight.lockLightingBuffer" for the center chunk in the neighborhood (for reading).
 */
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GSVector3)pos
                                        vertsBuffer:(GLfloat **)_vertsBuffer
                                        normsBuffer:(GLfloat **)_normsBuffer
                                    texCoordsBuffer:(GLfloat **)_texCoordsBuffer
                                        colorBuffer:(GLfloat **)_colorBuffer
                                        indexBuffer:(GLuint **)_indexBuffer
                                          voxelData:(GSNeighborhood *)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting
{
    if(!onlyDoingCounting && !(_vertsBuffer && _normsBuffer && _texCoordsBuffer && _colorBuffer && _indexBuffer)) {
        [NSException raise:NSInvalidArgumentException format:@"If countOnly is NO then pointers to buffers must be provided."];
    }
    
    GLsizei count = 0;

    GLfloat page = dirt;
    
    GLfloat x = pos.x;
    GLfloat y = pos.y;
    GLfloat z = pos.z;
    
    GLfloat minX = minP.x;
    GLfloat minY = minP.y;
    GLfloat minZ = minP.z;
    
    GSIntegerVector3 chunkLocalPos = {x-minX, y-minY, z-minZ};
    
    GSChunkVoxelData *centerVoxels = [chunks neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    
    if(isVoxelEmpty([centerVoxels voxelAtLocalPosition:chunkLocalPos])) {
        return count;
    }
    
    block_lighting_t sunlight;
    if(!onlyDoingCounting) {
        [centerVoxels.sunlight interpolateLightAtPoint:chunkLocalPos outLighting:&sunlight];
    }
    
    // TODO: add torch lighting to the world.
    block_lighting_t torchLight;
    if(!onlyDoingCounting) {
        bzero(&torchLight, sizeof(torchLight));
    }
    
    for(face_t i=0; i<FACE_NUM_FACES; ++i)
    {
        if([chunks emptyAtPoint:GSIntegerVector3_Add(chunkLocalPos, test[i])]) {
            count += 4;
            
            if(!onlyDoingCounting) {
                unsigned unpackedSunlight[4];
                unsigned unpackedTorchlight[4];
                
                if(i == FACE_TOP) {
                    page = side;
                }
                
                unpackBlockLightingValuesForVertex(sunlight.face[i], unpackedSunlight);
                unpackBlockLightingValuesForVertex(torchLight.face[i], unpackedTorchlight);
                
                for(size_t j=0; j<4; ++j)
                {
                    ssize_t tz = texCoord[j][i].z;
                    
                    addVertex(x+vertex[j][i].x, y+vertex[j][i].y, z+vertex[j][i].z,
                              normals[i].x, normals[i].y, normals[i].z,
                              texCoord[j][i].x, texCoord[j][i].y, tz<0?page:tz,
                              blockLight(unpackedSunlight[j], unpackedTorchlight[j]),
                              _vertsBuffer,
                              _normsBuffer,
                              _texCoordsBuffer,
                              _colorBuffer);
                }
            }
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


// Assumes the caller is already holding "lockGeometry".
- (NSData *)dataRepr
{
    NSMutableData *data = [[[NSMutableData alloc] init] autorelease];
    
    size_t len = sizeof(GLfloat) * 3 * numChunkVerts;
    [data appendBytes:&numChunkVerts length:sizeof(numChunkVerts)];
    [data appendBytes:vertsBuffer length:len];
    [data appendBytes:normsBuffer length:len];
    [data appendBytes:texCoordsBuffer length:len];
    [data appendBytes:colorBuffer length:len];
    
    return data;
}


// Assumes the caller is already holding "lockGeometry".
- (void)saveGeometryDataToFile
{
    NSURL *url = [NSURL URLWithString:[GSChunkGeometryData fileNameForGeometryDataFromMinP:minP]
                        relativeToURL:folder];
    
    [[self dataRepr] writeToURL:url atomically:YES];
}


// Assumes the caller is already holding "lockGeometry".
- (void)fillGeometryBuffersUsingDataRepr:(NSData *)data
{
    [self destroyGeometry];
    
    [data getBytes:&numChunkVerts range:NSMakeRange(0, sizeof(numChunkVerts))];
    
    assert(numChunkVerts % 4 == 0); // chunk geometry is all done with quads
    
    vertsBuffer = allocateGeometryBuffer(numChunkVerts);
    normsBuffer = allocateGeometryBuffer(numChunkVerts);
    texCoordsBuffer = allocateGeometryBuffer(numChunkVerts);
    colorBuffer = allocateGeometryBuffer(numChunkVerts);
    
    size_t len = sizeof(GLfloat) * 3 * numChunkVerts;
    
    [data getBytes:vertsBuffer     range:NSMakeRange(sizeof(numChunkVerts)+len*0, len)];
    [data getBytes:normsBuffer     range:NSMakeRange(sizeof(numChunkVerts)+len*1, len)];
    [data getBytes:texCoordsBuffer range:NSMakeRange(sizeof(numChunkVerts)+len*2, len)];
    [data getBytes:colorBuffer     range:NSMakeRange(sizeof(numChunkVerts)+len*3, len)];
    
    [self fillIndexBufferForGenerating:numChunkVerts];
}


- (BOOL)tryToLoadGeometryFromFile
{
    BOOL success = NO;
    
    if(!OSAtomicCompareAndSwapIntBarrier(0, 1, &updateInFlight)) {
        DebugLog(@"Can't load geometry: update already in-flight.");
        success = NO;
        goto cleanup1;
    }
    
    if(![lockGeometry tryLock]) {
        DebugLog(@"Can't load geometry: lockGeometry is already taken.");
        success = NO;
        goto cleanup2;
    }
    
    NSURL *url = [NSURL URLWithString:[GSChunkGeometryData fileNameForGeometryDataFromMinP:minP]
                        relativeToURL:folder];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        DebugLog(@"Can't load geometry: no geometry available on disk.");
        success = NO;
        goto cleanup3;
    }
    
    [self fillGeometryBuffersUsingDataRepr:[NSData dataWithContentsOfURL:url]];
    
    // Need to set this flag so VBO rendering code knows that it needs to regenerate from geometry on next redraw.
    // Updating a boolean should be atomic on x86_64 and i386;
    needsVBORegeneration = YES;
    
    // Geometry was loaded from disk, so we're not dirty anymore.
    dirty = NO;
    
    success = YES;
    
cleanup3:
    [lockGeometry unlockWithCondition:success?READY:!READY];
cleanup2:
    OSAtomicCompareAndSwapIntBarrier(1, 0, &updateInFlight); // reset
cleanup1:
    return success;
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
    assert(numVerts > 0);
    
    GLfloat *buffer = malloc(sizeof(GLfloat) * 3 * numVerts);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    
    return buffer;
}
