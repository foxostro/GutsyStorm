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

+ (NSData *)dataWithVoxelNeighborhood:(GSNeighborhood *)neighborhood minP:(GLKVector3)minCorner;

@end


@implementation GSChunkGeometryData
{
    NSData *_data;
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

- (id)initWithMinP:(GLKVector3)minCorner
            folder:(NSURL *)folder
      neighborhood:(GSNeighborhood *)neighborhood
{
    self = [super init];
    if (self) {
        minP = minCorner;
        
        NSURL *url = [NSURL URLWithString:[GSChunkGeometryData fileNameForGeometryDataFromMinP:self.minP]
                            relativeToURL:folder];
        NSError *error = nil;
        _data = [NSData dataWithContentsOfFile:[url path]
                                       options:NSDataReadingMapped
                                         error:&error];

        if(!_data) {
            //NSLog(@"failed to map the geometry data file at \"%@\": %@", url, error);
            [neighborhood readerAccessToVoxelDataUsingBlock:^{
                _data = [GSChunkGeometryData dataWithVoxelNeighborhood:neighborhood minP:self.minP];
                [_data writeToURL:url atomically:YES];
            }];
        }

        assert(_data);
    }
    
    return self;
}

- (GLsizei)copyVertsToBuffer:(struct vertex **)dst
{
    assert(dst);

    const struct chunk_geometry_header *restrict header = [_data bytes];
    const struct vertex * restrict vertsBuffer = ((void *)header) + sizeof(struct chunk_geometry_header);

    // consistency checks
    assert(header->w == CHUNK_SIZE_X);
    assert(header->h == CHUNK_SIZE_Y);
    assert(header->d == CHUNK_SIZE_Z);
    assert(header->len == (header->numChunkVerts * sizeof(struct vertex)));

    struct vertex *vertsCopy = malloc(header->len);
    if(!vertsCopy) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating vertsCopy in -copyVertsToBuffer:."];
    }

    memcpy(vertsCopy, vertsBuffer, header->len);

    *dst = vertsCopy;
    return header->numChunkVerts;
}

// Completely regenerate geometry for the chunk.
+ (NSData *)dataWithVoxelNeighborhood:(GSNeighborhood *)neighborhood minP:(GLKVector3)minCorner
{
    GLKVector3 pos;
    NSMutableArray *vertices;

    assert(neighborhood);

    const GLKVector3 maxCorner = GLKVector3Add(minCorner, GLKVector3Make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z));

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
    
    const GLsizei numChunkVerts = (GLsizei)[vertices count];
    assert(numChunkVerts % 4 == 0); // chunk geometry is all done with quads

    const uint32_t len = numChunkVerts * sizeof(struct vertex);
    const size_t capacity = sizeof(struct chunk_geometry_header) + len;
    NSMutableData *data = [[NSMutableData alloc] initWithBytesNoCopy:malloc(capacity) length:capacity freeWhenDone:YES];

    struct chunk_geometry_header * header = [data mutableBytes];
    struct vertex * vertsBuffer = (void *)header + sizeof(struct chunk_geometry_header);

    header->w = CHUNK_SIZE_X;
    header->h = CHUNK_SIZE_Y;
    header->d = CHUNK_SIZE_Z;
    header->numChunkVerts = numChunkVerts;
    header->len = len;

    // Take the vertices array and generate raw buffers for OpenGL to consume.
    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        GSVertex *v = vertices[i];
        vertsBuffer[i] = v.v;
    }

    // Iterate over all vertices and calculate lighting.
    applyLightToVertices(numChunkVerts, vertsBuffer,
                         [neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER].sunlight,
                         minCorner);

    return data;
}

@end


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
