//
//  FoxChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxIntegerVector3.h"
#import "FoxChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "FoxRay.h"
#import "FoxChunkStore.h"
#import "GSBoxedTerrainVertex.h"
#import "GSVoxel.h"
#import "FoxNeighborhood.h"
#import "FoxBlockMesh.h"
#import "FoxBlockMeshCube.h"
#import "FoxBlockMeshRamp.h"
#import "FoxBlockMeshInsideCorner.h"
#import "FoxBlockMeshOutsideCorner.h"
#import "SyscallWrappers.h"


struct fox_chunk_geometry_header
{
    uint8_t w, h, d;
    GLsizei numChunkVerts;
    uint32_t len;
};


static void applyLightToVertices(size_t numChunkVerts,
                                 struct GSTerrainVertex *vertsBuffer,
                                 FoxTerrainBuffer *sunlight,
                                 vector_float3 minP);

@interface FoxChunkGeometryData ()

+ (NSData *)dataWithSunlight:(GSChunkSunlightData *)sunlight minP:(vector_float3)minCorner;

@end


@implementation FoxChunkGeometryData
{
    NSData *_data;
}

@synthesize minP;

+ (FoxBlockMesh *)sharedMeshFactoryWithBlockType:(GSVoxelType)type
{
    static FoxBlockMesh *factories[NUM_VOXEL_TYPES] = {nil};
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        factories[VOXEL_TYPE_CUBE]           = [[FoxBlockMeshCube alloc] init];
        factories[VOXEL_TYPE_RAMP]           = [[FoxBlockMeshRamp alloc] init];
        factories[VOXEL_TYPE_CORNER_INSIDE]  = [[FoxBlockMeshInsideCorner alloc] init];
        factories[VOXEL_TYPE_CORNER_OUTSIDE] = [[FoxBlockMeshOutsideCorner alloc] init];
    });

    return factories[type];
}

+ (NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.geometry.dat", minP.x, minP.y, minP.z];
}

- (instancetype)initWithMinP:(vector_float3)minCorner
                      folder:(NSURL *)folder
                    sunlight:(GSChunkSunlightData *)sunlight
{
    self = [super init];
    if (self) {
        minP = minCorner;
        
        NSURL *url = [NSURL URLWithString:[FoxChunkGeometryData fileNameForGeometryDataFromMinP:self.minP]
                            relativeToURL:folder];
        NSError *error = nil;
        _data = [NSData dataWithContentsOfFile:[url path]
                                       options:NSDataReadingMapped
                                         error:&error];

        if(!_data) {
            //NSLog(@"failed to map the geometry data file at \"%@\": %@", url, error);
            _data = [FoxChunkGeometryData dataWithSunlight:sunlight minP:minP];
            [_data writeToURL:url atomically:YES];
        }

        assert(_data);
    }
    
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self; // all geometry objects are immutable, so return self instead of deep copying
}

- (GLsizei)copyVertsToBuffer:(struct GSTerrainVertex **)dst
{
    assert(dst);

    const struct fox_chunk_geometry_header *restrict header = [_data bytes];
    const struct GSTerrainVertex * restrict vertsBuffer = ((void *)header) + sizeof(struct fox_chunk_geometry_header);

    // consistency checks
    assert(header->w == CHUNK_SIZE_X);
    assert(header->h == CHUNK_SIZE_Y);
    assert(header->d == CHUNK_SIZE_Z);
    assert(header->len == (header->numChunkVerts * sizeof(struct GSTerrainVertex)));

    struct GSTerrainVertex *vertsCopy = malloc(header->len);
    if(!vertsCopy) {
        [NSException raise:@"Out of Memory" format:@"Out of memory allocating vertsCopy in -copyVertsToBuffer:."];
    }

    memcpy(vertsCopy, vertsBuffer, header->len);

    *dst = vertsCopy;
    return header->numChunkVerts;
}

// Completely regenerate geometry for the chunk.
+ (NSData *)dataWithSunlight:(GSChunkSunlightData *)sunlight minP:(vector_float3)minCorner
{
    vector_float3 pos;
    NSMutableArray<GSBoxedTerrainVertex *> *vertices;

    assert(sunlight);

    FoxNeighborhood *neighborhood = sunlight.neighborhood;

    const vector_float3 maxCorner = minCorner + vector_make(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z);

    vertices = [NSMutableArray<GSBoxedTerrainVertex *> new];

    // Iterate over all voxels in the chunk and generate geometry.
    FOR_BOX(pos, minCorner, maxCorner)
    {
        @autoreleasepool
        {
            vector_long3 chunkLocalPos = GSMakeIntegerVector3(pos.x-minCorner.x, pos.y-minCorner.y, pos.z-minCorner.z);
            GSVoxel voxel = [[neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER] voxelAtLocalPosition:chunkLocalPos];
            GSVoxelType type = voxel.type;
            assert(type < NUM_VOXEL_TYPES);

            if(type != VOXEL_TYPE_EMPTY) {
                FoxBlockMesh *factory = [FoxChunkGeometryData sharedMeshFactoryWithBlockType:type];
                [factory generateGeometryForSingleBlockAtPosition:pos
                                                       vertexList:vertices
                                                        voxelData:neighborhood
                                                             minP:minCorner];
            }
        }
    }

    const GLsizei numChunkVerts = (GLsizei)[vertices count];

    const uint32_t len = numChunkVerts * sizeof(struct GSTerrainVertex);
    const size_t capacity = sizeof(struct fox_chunk_geometry_header) + len;
    NSMutableData *data = [[NSMutableData alloc] initWithBytesNoCopy:malloc(capacity) length:capacity freeWhenDone:YES];

    struct fox_chunk_geometry_header * header = [data mutableBytes];
    struct GSTerrainVertex * vertsBuffer = (void *)header + sizeof(struct fox_chunk_geometry_header);

    header->w = CHUNK_SIZE_X;
    header->h = CHUNK_SIZE_Y;
    header->d = CHUNK_SIZE_Z;
    header->numChunkVerts = numChunkVerts;
    header->len = len;

    // Take the vertices array and generate raw buffers for OpenGL to consume.
    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        GSBoxedTerrainVertex *v = vertices[i];
        vertsBuffer[i] = v.v;
    }

    // Iterate over all vertices and calculate lighting.
    applyLightToVertices(numChunkVerts, vertsBuffer, sunlight.sunlight, minCorner);

    return data;
}

@end

static void applyLightToVertices(size_t numChunkVerts,
                                 struct GSTerrainVertex *vertsBuffer,
                                 FoxTerrainBuffer *sunlight,
                                 vector_float3 minP)
{
    assert(vertsBuffer);
    assert(sunlight);

    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        struct GSTerrainVertex *v = &vertsBuffer[i];
        
        vector_float3 vertexPos = vector_make(v->position[0], v->position[1], v->position[2]);
        vector_long3 normal = (vector_long3){v->normal[0], v->normal[1], v->normal[2]};

        uint8_t sunlightValue = [sunlight lightForVertexAtPoint:vertexPos
                                                     withNormal:normal
                                                           minP:minP];

        vector_float4 color = {0};

        color.y = 204.0f * (sunlightValue / (float)CHUNK_LIGHTING_MAX) + 51.0f; // sunlight in the green channel

        v->color[0] = color.x;
        v->color[1] = color.y;
        v->color[2] = color.z;
        v->color[3] = color.w;
    }
}
