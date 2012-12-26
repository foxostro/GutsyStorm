//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSChunkGeometryData.h"
#import "GSChunkVoxelData.h"
#import "GSChunkStore.h"
#import "GSVertex.h"

#define ARRAY_LEN(array) (sizeof(array)/sizeof(array[0]))
#define SIZEOF_STRUCT_ARRAY_ELEMENT(t, m) sizeof(((t*)0)->m[0])
#define SWAP(x, y) do { typeof(x) temp##x##y = x; x = y; y = temp##x##y; } while (0)

struct chunk_geometry_header
{
    uint8_t w, h, d;
    uint16_t numChunkVerts;
    uint32_t len;
};

extern int checkGLErrors(void);

static void drawChunkVBO(GLsizei numIndicesForDrawing, GLuint vbo);
static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo);
static void packVertex(struct vertex *vertices,  GLKVector3 position, GLKVector3 normal, GLKVector3 texCoord, GLKVector3 color);
static void * allocateVertexMemory(size_t numVerts);

static inline GLKVector3 blockLight(unsigned sunlight, unsigned torchLight)
{
    // Pack sunlight into the Green channel, and torch light into the Blue channel.
    return GLKVector3Make(0,
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

const static GLKVector3 normals[FACE_NUM_FACES] = {
    {0, 1, 0},
    {0, -1, 0},
    {0, 0, 1},
    {0, 1, -1},
    {1, 0, 0},
    {-1, 0, 0},
};

const static GLKVector3 vertex[4][FACE_NUM_FACES] = {
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

+ (GLushort *)sharedIndexBuffer;

- (void)destroyGeometry;
- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)chunks;
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                        vertsBuffer:(struct vertex **)_vertices
                                          voxelData:(GSNeighborhood *)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting;
- (NSData *)dataRepr;
- (void)saveGeometryDataToFile;
- (NSError *)fillGeometryBuffersUsingDataRepr:(NSData *)data;
- (BOOL)tryToLoadGeometryFromFile;

@end


@implementation GSChunkGeometryData

@synthesize dirty;


+ (NSString *)fileNameForGeometryDataFromMinP:(GLKVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.geometry.dat", minP.x, minP.y, minP.z];
}


- (id)initWithMinP:(GLKVector3)_minP
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
        numChunkVerts = 0;
        dirty = YES;
        updateInFlight = 0;
        
        /* VBO data is not lock protected and is either exclusively accessed on the main thread
         * or is updated in ways that do not require locking for atomicity.
         */
        vbo = 0;
        numIndicesForDrawing = 0;
        needsVBORegeneration = NO;
        
        // Frustum-Box testing requires the corners of the cube, so pre-calculate them here.
        corners[0] = minP;
        corners[1] = GLKVector3Add(minP, GLKVector3Make(CHUNK_SIZE_X, 0,            0));
        corners[2] = GLKVector3Add(minP, GLKVector3Make(CHUNK_SIZE_X, 0,            CHUNK_SIZE_Z));
        corners[3] = GLKVector3Add(minP, GLKVector3Make(0,            0,            CHUNK_SIZE_Z));
        corners[4] = GLKVector3Add(minP, GLKVector3Make(0,            CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[5] = GLKVector3Add(minP, GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));
        corners[6] = GLKVector3Add(minP, GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, 0));
        corners[7] = GLKVector3Add(minP, GLKVector3Make(0,            CHUNK_SIZE_Y, 0));
        
        visible = NO;
        
        // Try to load geometry from file so we have something to show before regeneration finishes.
        [self tryToLoadGeometryFromFile];
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
            
            // Need to set this flag so VBO rendering code knows that it needs to regenerate from geometry on next redraw.
            // Updating a boolean should be atomic on x86_64 and i386;
            needsVBORegeneration = YES;
            
            // Cache geometry buffers on disk for next time.
            [self saveGeometryDataToFile];
            
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
    
    if(allowVBOGeneration && needsVBORegeneration && [lockGeometry tryLockWhenCondition:READY]) {
        if(!vbo) {
            glGenBuffers(1, &vbo);
        }
        
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, numChunkVerts * sizeof(struct vertex), vertsBuffer, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
        numIndicesForDrawing = numChunkVerts;
        needsVBORegeneration = NO; // reset
        didGenerateVBOs = YES;
        
        [lockGeometry unlock];
    }
    
    drawChunkVBO(numIndicesForDrawing, vbo);

    return didGenerateVBOs;
}


- (void)dealloc
{
    dispatch_async(dispatch_get_main_queue(), ^{
        syncDestroySingleVBO(glContext, vbo);
    });
    
    [self destroyGeometry];
    [lockGeometry release];
    [glContext release];
    [folder release];
    dispatch_release(groupForSaving);
    [super dealloc];
}

@end


@implementation GSChunkGeometryData (Private)

+ (GLushort *)sharedIndexBuffer
{
    static dispatch_once_t onceToken;
    static GLushort *buffer = NULL;
    dispatch_once(&onceToken, ^{
        // Make sure the index buffer can handle this many verts.
        const GLsizei maxChunkVerts = (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z);
        assert(maxChunkVerts < (1UL << (sizeof(GLushort)*8)));
        
        // Take the indices array and generate a raw index buffer that OpenGL can consume.
        buffer = malloc(sizeof(GLushort) * maxChunkVerts);
        if(!buffer) {
            [NSException raise:@"Out of Memory" format:@"Out of memory allocating index buffer."];
        }
        
        for(GLsizei i = 0; i < maxChunkVerts; ++i)
        {
            buffer[i] = i; // a simple linear walk
        }
    });
    
    return buffer;
}

/* Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight.lockLightingBuffer" for the center chunk in the neighborhood (for reading).
 */
- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)chunks
{
    GLKVector3 pos;
    
    // Iterate over all voxels in the chunk and count the number of vertices that would be generated.
    numChunkVerts = 0;
    FOR_BOX(pos, minP, maxP)
    {
        numChunkVerts += [self generateGeometryForSingleBlockAtPosition:pos
                                                            vertsBuffer:NULL
                                                              voxelData:chunks
                                                      onlyDoingCounting:YES];
    }
    assert(numChunkVerts % 4 == 0); // chunk geometry is all done with quads
    
    // Take the vertices array and generate raw buffers for OpenGL to consume.
    vertsBuffer = allocateVertexMemory(numChunkVerts);
    
    // Iterate over all voxels in the chunk and generate geometry.
    struct vertex *_vertsBuffer = vertsBuffer;
    FOR_BOX(pos, minP, maxP)
    {
        [self generateGeometryForSingleBlockAtPosition:pos
                                           vertsBuffer:&_vertsBuffer
                                             voxelData:chunks
                                     onlyDoingCounting:NO];
    }
}


// Assumes the caller is already holding "lockGeometry".
- (void)destroyGeometry
{
    free(vertsBuffer);
    vertsBuffer = NULL;
    numChunkVerts = 0;
}


/* Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight.lockLightingBuffer" for the center chunk in the neighborhood (for reading).
 */
- (GLsizei)generateGeometryForSingleBlockAtPosition:(GLKVector3)pos
                                        vertsBuffer:(struct vertex **)_vertices
                                          voxelData:(GSNeighborhood *)chunks
                                  onlyDoingCounting:(BOOL)onlyDoingCounting
{
    if(!onlyDoingCounting && !_vertices) {
        [NSException raise:NSInvalidArgumentException format:@"If countOnly is NO then _vertices must be provided"];
    }
    
    GLsizei count = 0;

    GLfloat page = dirt;
    
    GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minP.x, pos.y-minP.y, pos.z-minP.z);
    
    GSChunkVoxelData *centerVoxels = [chunks neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    
    if([centerVoxels voxelAtLocalPosition:chunkLocalPos].type == VOXEL_TYPE_EMPTY) {
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
                    
                    packVertex(*_vertices,
                               GLKVector3Add(vertex[j][i], pos),
                               normals[i],
                               GLKVector3Make(texCoord[j][i].x, texCoord[j][i].y, tz<0?page:tz),
                               blockLight(unpackedSunlight[j], unpackedTorchlight[j]));
                    
                    (*_vertices)++;
                }
            }
        }
    }
    
    return count;
}


// Assumes the caller is already holding "lockGeometry".
- (NSData *)dataRepr
{
    NSMutableData *data = [[[NSMutableData alloc] init] autorelease];
    
    assert(numChunkVerts < (1UL << (sizeof(GLushort)*8))); // make sure the number of vertices can be stored in a 16-bit uint.
    
    struct chunk_geometry_header header;
    header.w = CHUNK_SIZE_X;
    header.h = CHUNK_SIZE_Y;
    header.d = CHUNK_SIZE_Z;
    header.numChunkVerts = numChunkVerts;
    header.len = numChunkVerts * sizeof(struct vertex);
    
    [data appendBytes:&header length:sizeof(header)];
    [data appendBytes:vertsBuffer length:header.len];
    
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
- (NSError *)fillGeometryBuffersUsingDataRepr:(NSData *)data
{
    struct chunk_geometry_header header;
    
    if(!data) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"Geometry data is nil."}];
    }
    
    [self destroyGeometry];
    
    [data getBytes:&header range:NSMakeRange(0, sizeof(struct chunk_geometry_header))];
    
    if((header.w != CHUNK_SIZE_X) || (header.h != CHUNK_SIZE_Y) || (header.d != CHUNK_SIZE_Z)) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"Geometry data is for chunk of the wrong size."}];
    }
    
    if(header.numChunkVerts <= 0) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"numChunkVerts <= 0"}];
    }
    
    if((header.numChunkVerts % 4) != 0) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"numChunkVerts%4 != 0"}];
    }
    
    const size_t expectedLen = header.numChunkVerts * sizeof(struct vertex);
    if(expectedLen != header.len) {
        return [NSError errorWithDomain:GSErrorDomain
                                   code:GSInvalidChunkDataOnDiskError
                               userInfo:@{NSLocalizedFailureReasonErrorKey:@"Geometry data length is not as unexpected."}];
    }
    
    numChunkVerts = header.numChunkVerts;
    vertsBuffer = allocateVertexMemory(numChunkVerts);
    [data getBytes:vertsBuffer range:NSMakeRange(sizeof(struct chunk_geometry_header), header.len)];
    
    return nil; // Success!
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
    
    NSString *path = [GSChunkGeometryData fileNameForGeometryDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:path relativeToURL:folder];
    
    if(NO == [url checkResourceIsReachableAndReturnError:NULL]) {
        DebugLog(@"Can't load geometry: file not present.");
        success = NO;
        goto cleanup3;
    }
    
    NSError *error = [self fillGeometryBuffersUsingDataRepr:[NSData dataWithContentsOfURL:url]];
    if(nil != error) {
        DebugLog(@"Can't load geometry: %@", error.localizedDescription);
        success = NO;
        goto cleanup3;
    }
    
    // Success!
    needsVBORegeneration = YES;
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


static void drawChunkVBO(GLsizei numIndicesForDrawing, GLuint vbo)
{
    if(!vbo) {
        return;
    }
    
    if(numIndicesForDrawing <= 0) {
        return;
    }
    
    const GLushort const *indices = [GSChunkGeometryData sharedIndexBuffer];
    
    assert(checkGLErrors() == 0);
    
    assert(numIndicesForDrawing < (CHUNK_SIZE_X*CHUNK_SIZE_Y*CHUNK_SIZE_Z));
    assert(indices);
    
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    
    // Verify that vertex attribute formats are consistent with in-memory storage.
    assert(sizeof(GLfloat) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, position));
    assert(sizeof(GLbyte)  == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, normal));
    assert(sizeof(GLshort) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, texCoord));
    assert(sizeof(GLubyte) == SIZEOF_STRUCT_ARRAY_ELEMENT(struct vertex, color));
    
    const GLvoid *offsetVertex   = (const GLvoid *)offsetof(struct vertex, position);
    const GLvoid *offsetNormal   = (const GLvoid *)offsetof(struct vertex, normal);
    const GLvoid *offsetTexCoord = (const GLvoid *)offsetof(struct vertex, texCoord);
    const GLvoid *offsetColor    = (const GLvoid *)offsetof(struct vertex, color);
    
    const GLsizei stride = sizeof(struct vertex);
    glVertexPointer(  3, GL_FLOAT,         stride, offsetVertex);
    glNormalPointer(     GL_BYTE,          stride, offsetNormal);
    glTexCoordPointer(3, GL_SHORT,         stride, offsetTexCoord);
    glColorPointer(   4, GL_UNSIGNED_BYTE, stride, offsetColor);
    
    assert(checkGLErrors() == 0);
    glDrawElements(GL_QUADS, numIndicesForDrawing, GL_UNSIGNED_SHORT, indices);
    assert(checkGLErrors() == 0);
}


static void syncDestroySingleVBO(NSOpenGLContext *context, GLuint vbo)
{
    assert(context);
    if(vbo) {
        [context makeCurrentContext];
        CGLLockContext((CGLContextObj)[context CGLContextObj]); // protect against display link thread
        glDeleteBuffers(1, &vbo);
        CGLUnlockContext((CGLContextObj)[context CGLContextObj]);
    }
}


static void packVertex(struct vertex *vertex,  GLKVector3 position, GLKVector3 normal, GLKVector3 texCoord, GLKVector3 color)
{
    assert(vertex);
    
    vertex->position[0] = position.x;
    vertex->position[1] = position.y;
    vertex->position[2] = position.z;
    
    vertex->normal[0] = normal.x;
    vertex->normal[1] = normal.y;
    vertex->normal[2] = normal.z;
    
    vertex->texCoord[0] = texCoord.x;
    vertex->texCoord[1] = texCoord.y;
    vertex->texCoord[2] = texCoord.z;
    
    vertex->color[0] = color.x * 255;
    vertex->color[1] = color.y * 255;
    vertex->color[2] = color.z * 255;
    vertex->color[3] = 1;
}


// Allocate a buffer for use in geometry generation and VBOs.
static void * allocateVertexMemory(size_t numVerts)
{
    assert(numVerts > 0);
    
    void *buffer = malloc(sizeof(struct vertex) * numVerts);
    if(!buffer) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating chunk buffer."];
    }
    
    return buffer;
}
