//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSIntegerVector3.h"
#import "GSChunkGeometryData.h"
#import "GSChunkVoxelData.h"
#import "GSRay.h"
#import "GSChunkStore.h"
#import "GSVertex.h"
#import "Voxel.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshCube.h"
#import "GSBlockMeshRamp.h"
#import "GSBlockMeshInsideCorner.h"
#import "GSBlockMeshOutsideCorner.h"
#import "SyscallWrappers.h"

#define SIZEOF_STRUCT_ARRAY_ELEMENT(t, m) sizeof(((t*)0)->m[0])

struct chunk_geometry_header
{
    uint8_t w, h, d;
    GLsizei numChunkVerts;
    uint32_t len;
};

static void * allocateVertexMemory(size_t numVerts);
static void applyLightToVertices(size_t numChunkVerts,
                                 struct vertex *vertsBuffer,
                                 GSBuffer *sunlight,
                                 GLKVector3 minP);


@interface GSChunkGeometryData ()

- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)voxelData;

@end


@implementation GSChunkGeometryData
{
    GLsizei _numChunkVerts;
    struct vertex *_vertsBuffer;
}

@synthesize minP;

+ (GSBlockMesh *)sharedMeshFactoryWithBlockType:(voxel_type_t)type
{
    static GSBlockMesh *factories[NUM_VOXEL_TYPES] = {nil};
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        factories[VOXEL_TYPE_CUBE]           = [[GSBlockMeshCube alloc] init];
        factories[VOXEL_TYPE_RAMP]           = [[GSBlockMeshRamp alloc] init];
        factories[VOXEL_TYPE_CORNER_INSIDE]  = [[GSBlockMeshInsideCorner alloc] init];
        factories[VOXEL_TYPE_CORNER_OUTSIDE] = [[GSBlockMeshOutsideCorner alloc] init];
    });

    return factories[type];
}

+ (NSString *)fileNameForGeometryDataFromMinP:(GLKVector3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.geometry.dat", minP.x, minP.y, minP.z];
}

- (id)initWithMinP:(GLKVector3)mp neighborhood:(GSNeighborhood *)neighborhood
{
    self = [super init];
    if (self) {
        minP = mp;
        [neighborhood readerAccessToVoxelDataUsingBlock:^{
            [self fillGeometryBuffersUsingVoxelData:neighborhood];
        }];
    }
    
    return self;
}

- (void)dealloc
{
    free(_vertsBuffer);
}

- (GLsizei)copyVertsToBuffer:(struct vertex **)dst
{
    assert(dst);

    const GLsizei count = _numChunkVerts;
    struct vertex *vertsCopy = malloc(_numChunkVerts * count);
    if(!vertsCopy) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating vertsCopy in -copyVertsToBuffer:."];
    }

    memcpy(vertsCopy, _vertsBuffer, sizeof(struct vertex) * count);

    *dst = vertsCopy;
    return count;
}

/* Completely regenerate geometry for the chunk.
 *
 * Assumes caller is already holding the following locks:
 * "lockGeometry"
 * "lockVoxelData" for all chunks in the neighborhood (for reading).
 * "sunlight" must be locked for reading for the center chunk in the neighborhood.
 */
- (void)fillGeometryBuffersUsingVoxelData:(GSNeighborhood *)neighborhood
{
    GLKVector3 pos;
    NSMutableArray *vertices;

    assert(neighborhood);

    GLKVector3 minCorner = self.minP;
    GLKVector3 maxCorner = GLKVector3Add(minCorner, GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));

    vertices = [[NSMutableArray alloc] init];

    // Iterate over all voxels in the chunk and generate geometry.
    FOR_BOX(pos, minCorner, maxCorner)
    {
        @autoreleasepool
        {
            GSIntegerVector3 chunkLocalPos = GSIntegerVector3_Make(pos.x-minCorner.x, pos.y-minCorner.y, pos.z-minCorner.z);
            voxel_type_t type = [[neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER] voxelAtLocalPosition:chunkLocalPos].type;

            if(type != VOXEL_TYPE_EMPTY) {
                GSBlockMesh *factory = [GSChunkGeometryData sharedMeshFactoryWithBlockType:type];
                [factory generateGeometryForSingleBlockAtPosition:pos
                                                       vertexList:vertices
                                                        voxelData:neighborhood
                                                             minP:minCorner];
            }
        }
    }
    
    _numChunkVerts = (GLsizei)[vertices count];
    assert(_numChunkVerts % 4 == 0); // chunk geometry is all done with quads

    // Take the vertices array and generate raw buffers for OpenGL to consume.
    _vertsBuffer = allocateVertexMemory(_numChunkVerts);
    for(GLsizei i=0; i<_numChunkVerts; ++i)
    {
        GSVertex *v = vertices[i];
        _vertsBuffer[i] = v.v;
    }

    // Iterate over all vertices and calculate lighting.
    applyLightToVertices(_numChunkVerts, _vertsBuffer,
                         [neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER].sunlight,
                         minCorner);
}

@end


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

static void applyLightToVertices(size_t numChunkVerts,
                                 struct vertex *vertsBuffer,
                                 GSBuffer *sunlight,
                                 GLKVector3 minP)
{
    assert(vertsBuffer);
    assert(sunlight);

    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        struct vertex *v = &vertsBuffer[i];
        
        GLKVector3 vertexPos = GLKVector3MakeWithArray(v->position);
        GSIntegerVector3 normal = GSIntegerVector3_MakeWithGLubyte3(v->normal);

        uint8_t sunlightValue = [sunlight lightForVertexAtPoint:vertexPos
                                                     withNormal:normal
                                                           minP:minP];

        GLKVector4 color = {0};

        color.g = 204.0f * (sunlightValue / (float)CHUNK_LIGHTING_MAX) + 51.0f; // sunlight in the green channel

        v->color[0] = color.v[0];
        v->color[1] = color.v[1];
        v->color[2] = color.v[2];
        v->color[3] = color.v[3];
    }
}
