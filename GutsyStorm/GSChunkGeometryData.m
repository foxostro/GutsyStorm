//
//  GSChunkGeometryData.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"
#import "GSRay.h"
#import "GSTerrainChunkStore.h"
#import "GSVoxel.h"
#import "GSVoxelNeighborhood.h"
#import "SyscallWrappers.h"
#import "GSActivity.h"
#import "GSErrorCodes.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshCube.h"
#import "GSBlockMeshRamp.h"
#import "GSBlockMeshInsideCorner.h"
#import "GSBlockMeshOutsideCorner.h"


#define GEO_MAGIC ('moeg')
#define GEO_VERSION (0)


struct GSChunkGeometryHeader
{
    uint32_t magic;
    uint32_t version;
    uint32_t w, h, d;
    GLsizei numChunkVerts;
    uint32_t len;
};


static inline vector_float3 subChunkMinCorner(vector_float3 minP, NSUInteger i)
{
    return minP + vector_make(0, CHUNK_SIZE_Y * i / GSNumGeometrySubChunks, 0);
}


static inline vector_float3 subChunkMaxCorner(vector_float3 minP, NSUInteger i)
{
    return subChunkMinCorner(minP, i) + vector_make(CHUNK_SIZE_X, CHUNK_SIZE_Y / GSNumGeometrySubChunks, CHUNK_SIZE_Z);
}


static NSArray<GSBoxedTerrainVertex *> * _Nonnull
createVertices(GSChunkSunlightData * _Nonnull sunlight,
               vector_float3 chunkMinP,
               vector_float3 minCorner,
               vector_float3 maxCorner);


static void applyLightToVertices(size_t numChunkVerts,
                                 GSTerrainVertex * _Nonnull vertsBuffer,
                                 GSTerrainBuffer * _Nonnull sunlight,
                                 vector_float3 minP);


@interface GSChunkGeometryData ()

- (void)generateDataWithSunlight:(nonnull GSChunkSunlightData *)sunlight minP:(vector_float3)minCorner;

@end


@implementation GSChunkGeometryData

@synthesize minP;

+ (nonnull NSString *)fileNameForGeometryDataFromMinP:(vector_float3)minP
{
    return [NSString stringWithFormat:@"%.0f_%.0f_%.0f.geometry.dat", minP.x, minP.y, minP.z];
}

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nonnull NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        allowLoading:(BOOL)allowLoading
{
    NSParameterAssert(folder);
    NSParameterAssert(sunlight);
    NSParameterAssert(queueForSaving);
    NSParameterAssert(groupForSaving);

    if (self = [super init]) {
        GSStopwatchTraceStep(@"Initializing geometry chunk %@", [GSBoxedVector boxedVectorWithVector:minCorner]);

        minP = minCorner;

        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        
        BOOL failedToLoadFromFile = YES;
        NSString *fileName = [[self class] fileNameForGeometryDataFromMinP:minCorner];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:folder];
        NSError *error = nil;
        
        if (allowLoading) {
            _data = [NSData dataWithContentsOfFile:[url path]
                                           options:NSDataReadingMapped
                                             error:&error];
        }

        if (!allowLoading) {
            // do nothing
        } else if(!_data) {
            if ([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == 260)) {
                // File not found. We don't have to log this one because it's common and we know how to recover.
            } else {
                NSLog(@"ERROR: Failed to map the geometry data file at \"%@\": %@", fileName, error);
            }
        } else if (![self validateGeometryData:_data error:&error]) {
            NSLog(@"ERROR: Failed to validate the geometry data file at \"%@\": %@", fileName, error);
        } else {
            failedToLoadFromFile = NO; // success!
            GSStopwatchTraceStep(@"Loaded geometry for chunk from file.");
        }

        if (failedToLoadFromFile) {
            for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
            {
                _vertices[i] = createVertices(sunlight,
                                              minCorner,
                                              subChunkMinCorner(minCorner, i),
                                              subChunkMaxCorner(minCorner, i));
            }
            GSStopwatchTraceStep(@"Done generating triangles.");

            [self generateDataWithSunlight:sunlight minP:minP];
            [self saveData:_data url:url queue:queueForSaving group:groupForSaving];
        }
        
        if (!_data) {
            [NSException raise:NSGenericException
                        format:@"Failed to fetch or generate the geometry chunk at \"%@\"", fileName];
        }

        GSStopwatchTraceStep(@"Done initializing geometry chunk %@", [GSBoxedVector boxedVectorWithVector:minCorner]);
    }
    
    return self;
}

- (nonnull instancetype)initWithMinP:(vector_float3)minCorner
                              folder:(nonnull NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                            vertices:(NSArray * __strong _Nonnull [GSNumGeometrySubChunks])vertices
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
{
    NSParameterAssert(folder);
    NSParameterAssert(sunlight);
    NSParameterAssert(queueForSaving);
    NSParameterAssert(groupForSaving);
    
    if (self = [super init]) {
        GSStopwatchTraceStep(@"Initializing geometry chunk %@", [GSBoxedVector boxedVectorWithVector:minCorner]);
        
        minP = minCorner;
        
        _groupForSaving = groupForSaving; // dispatch group used for tasks related to saving chunks to disk
        _queueForSaving = queueForSaving; // dispatch queue used for saving changes to chunks
        _folder = folder;
        
        for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
        {
            _vertices[i] = vertices[i];
        }
        
        NSString *fileName = [[self class] fileNameForGeometryDataFromMinP:minCorner];
        NSURL *url = [NSURL URLWithString:fileName relativeToURL:folder];
        
        [self generateDataWithSunlight:sunlight minP:minP];
        [self saveData:_data url:url queue:queueForSaving group:groupForSaving];
        
        if (!_data) {
            [NSException raise:NSGenericException
                        format:@"Failed to fetch or generate the geometry chunk at \"%@\"", fileName];
        }
        
        GSStopwatchTraceStep(@"Done initializing geometry chunk %@", [GSBoxedVector boxedVectorWithVector:minCorner]);
    }
    
    return self;
}

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // all geometry objects are immutable, so return self instead of deep copying
}

- (nonnull instancetype)copyWithSunlight:(nonnull GSChunkSunlightData *)sunlight
                     invalidatedAreaMinP:(vector_long3)invalidatedAreaMinP
                     invalidatedAreaMaxP:(vector_long3)invalidatedAreaMaxP
{
    NSParameterAssert(sunlight);
    
    if (!_vertices) {
        return [[[self class] alloc] initWithMinP:minP
                                           folder:_folder
                                         sunlight:sunlight
                                   groupForSaving:_groupForSaving
                                   queueForSaving:_queueForSaving
                                     allowLoading:NO];
    }

    BOOL invalidatedSubChunk[GSNumGeometrySubChunks];
    {
        struct { vector_float3 mins, maxs; } a, b;

        a.mins = GSCastToFloat3(invalidatedAreaMinP) + minP;
        a.maxs = GSCastToFloat3(invalidatedAreaMaxP) + minP;

        for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
        {
            b.mins = subChunkMinCorner(minP, i);
            b.maxs = subChunkMaxCorner(minP, i);
            
            BOOL intersects = (a.mins.x <= b.maxs.x) && (a.maxs.x >= b.mins.x) &&
                              (a.mins.y <= b.maxs.y) && (a.maxs.y >= b.mins.y) &&
                              (a.mins.z <= b.maxs.z) && (a.maxs.z >= b.mins.z);
            
            invalidatedSubChunk[i] = intersects;
        }
    }
    
    NSArray<GSBoxedTerrainVertex *> *updatedVertices[GSNumGeometrySubChunks] = {nil};
    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        NSArray<GSBoxedTerrainVertex *> *vertices;

        if (invalidatedSubChunk[i]) {
            vertices = createVertices(sunlight,
                                      minP,
                                      subChunkMinCorner(minP, i),
                                      subChunkMaxCorner(minP, i));
        } else {
            vertices = _vertices[i];
        }

        updatedVertices[i] = vertices;
    }

    return [[[self class] alloc] initWithMinP:minP
                                       folder:_folder
                                     sunlight:sunlight
                                     vertices:updatedVertices
                               groupForSaving:_groupForSaving
                               queueForSaving:_queueForSaving];
}

- (BOOL)validateGeometryData:(nonnull NSData *)data error:(NSError **)error
{
    NSParameterAssert(data);
    
    const struct GSChunkGeometryHeader *header = [data bytes];

    if (!header) {
        if (error) {
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : @"Cannot get pointer to header."}];
        }
        return NO;
    }

    if (header->magic != GEO_MAGIC) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected magic number in geometry data file: found %d " \
                              @"but expected %d", header->magic, GEO_MAGIC];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSBadMagicNumberError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->version != GEO_VERSION) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected version number in geometry data file: found %d " \
                              @"but expected %d", header->version, GEO_VERSION];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnsupportedVersionError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    BOOL acceptableChunkSize = (header->w==CHUNK_SIZE_X) && (header->h==CHUNK_SIZE_Y) && (header->d==CHUNK_SIZE_Z);

    if (!acceptableChunkSize) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Unexpected chunk size used in geometry data: found " \
                              @"(%d,%d,%d) but expected (%d,%d,%d)",
                              header->w, header->h, header->d,
                              CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z];
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedChunkDimensionsError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    if (header->len != (header->numChunkVerts * sizeof(GSTerrainVertex))) {
        if (error) {
            NSString *desc = @"Unexpected number of bytes used in geometry data file";
            *error = [NSError errorWithDomain:GSErrorDomain
                                         code:GSUnexpectedDataSizeError
                                     userInfo:@{NSLocalizedDescriptionKey : desc}];
        }
        return NO;
    }
    
    return YES;
}

- (nonnull GSTerrainVertexNoNormal *)copyVertsReturningCount:(nonnull GLsizei *)outCount
{
    NSParameterAssert(outCount);

    const struct GSChunkGeometryHeader * restrict header = [_data bytes];
    const GSTerrainVertex * restrict vertsBuffer = ((void *)header) + sizeof(struct GSChunkGeometryHeader);
    GLsizei count = header->numChunkVerts;

    BOOL acceptableChunkSize = (header->w==CHUNK_SIZE_X) && (header->h==CHUNK_SIZE_Y) && (header->d==CHUNK_SIZE_Z);
    
    if (!acceptableChunkSize) {
        [NSException raise:NSGenericException format:@"Unacceptable chunk size for geometry chunk."];
    }

    if (header->len != (header->numChunkVerts * sizeof(GSTerrainVertex))) {
        [NSException raise:NSGenericException format:@"Unexpected length for geometry data."];
    }

    GSTerrainVertexNoNormal *vertsCopy = malloc(count * sizeof(GSTerrainVertexNoNormal));
    if(!vertsCopy) {
        [NSException raise:NSMallocException format:@"Out of memory allocating vertsCopy in -copyVertsToBuffer:."];
    }
    
    for(size_t i = 0; i < count; ++i)
    {
        // This works because we have ensured the memory layouts of the two structs are very similar.
        memcpy(&vertsCopy[i], &vertsBuffer[i], sizeof(GSTerrainVertexNoNormal));
    }

    *outCount = count;
    return vertsCopy;
}

- (void)generateDataWithSunlight:(nonnull GSChunkSunlightData *)sunlight minP:(vector_float3)minCorner
{
    NSParameterAssert(sunlight);
    
    NSMutableArray *entireVertices = [[NSMutableArray alloc] init];
    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        [entireVertices addObjectsFromArray:_vertices[i]];
    }

    const GLsizei numChunkVerts = (GLsizei)[entireVertices count];

    const uint32_t len = numChunkVerts * sizeof(GSTerrainVertex);
    const size_t capacity = sizeof(struct GSChunkGeometryHeader) + len;
    NSMutableData *data = [[NSMutableData alloc] initWithBytesNoCopy:malloc(capacity) length:capacity freeWhenDone:YES];
    if(!data) {
        [NSException raise:NSMallocException format:@"Out of memory allocating `data' in -dataWithSunlight:minP:."];
    }

    struct GSChunkGeometryHeader * header = [data mutableBytes];
    GSTerrainVertex * vertsBuffer = (void *)header + sizeof(struct GSChunkGeometryHeader);

    header->magic = GEO_MAGIC;
    header->version = GEO_VERSION;
    header->w = CHUNK_SIZE_X;
    header->h = CHUNK_SIZE_Y;
    header->d = CHUNK_SIZE_Z;
    header->numChunkVerts = numChunkVerts;
    header->len = len;

    // Take the vertices array and generate raw buffers for OpenGL to consume.
    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        GSBoxedTerrainVertex *v = entireVertices[i];
        vertsBuffer[i] = v.v;
    }

    // Iterate over all vertices and calculate lighting.
    applyLightToVertices(numChunkVerts, vertsBuffer, sunlight.sunlight, minCorner);
    
    _data = data;
}

- (void)saveData:(nonnull NSData *)data
             url:(nonnull NSURL *)url
           queue:(nonnull dispatch_queue_t)queue
           group:(nonnull dispatch_group_t)group
{
    dispatch_group_enter(group);
    
    dispatch_data_t dd = dispatch_data_create([data bytes], [data length],
                                              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                              DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    dispatch_async(queue, ^{
        int fd = Open(url, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP);
        
        dispatch_write(fd, dd, queue, ^(dispatch_data_t data, int error) {
            Close(fd);
            
            if(error) {
                raiseExceptionForPOSIXError(error, [NSString stringWithFormat:@"error with write(fd=%u)", fd]);
            }
            
            dispatch_group_leave(group);
        });
    });
}

- (void)invalidate
{
    NSString *fileName = [[self class] fileNameForGeometryDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end

static NSArray<GSBoxedTerrainVertex *> * _Nonnull
createVertices(GSChunkSunlightData * _Nonnull sunlight,
               vector_float3 chunkMinP,
               vector_float3 minCorner,
               vector_float3 maxCorner)
{
    assert(sunlight);
    
    static GSBlockMesh *factories[NUM_VOXEL_TYPES] = {nil};
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        factories[VOXEL_TYPE_CUBE]           = [[GSBlockMeshCube alloc] init];
        factories[VOXEL_TYPE_RAMP]           = [[GSBlockMeshRamp alloc] init];
        factories[VOXEL_TYPE_CORNER_INSIDE]  = [[GSBlockMeshInsideCorner alloc] init];
        factories[VOXEL_TYPE_CORNER_OUTSIDE] = [[GSBlockMeshOutsideCorner alloc] init];
    });
    
    GSVoxelNeighborhood *neighborhood = sunlight.neighborhood;
    GSChunkVoxelData *center = [neighborhood neighborAtIndex:CHUNK_NEIGHBOR_CENTER];
    
    // Iterate over all voxels in the chunk and generate geometry.
    NSMutableArray<GSBoxedTerrainVertex *> *vertices = [[NSMutableArray alloc] init];
    vector_float3 pos;
    FOR_BOX(pos, minCorner, maxCorner)
    {
        vector_long3 chunkLocalPos = GSCastToIntegerVector3(pos - chunkMinP);
        GSVoxel voxel = [center voxelAtLocalPosition:chunkLocalPos];
        GSVoxelType type = voxel.type;
        
        if ((type < NUM_VOXEL_TYPES) && (type != VOXEL_TYPE_EMPTY)) {
            GSBlockMesh *factory = factories[type];
            [factory generateGeometryForSingleBlockAtPosition:pos
                                                   vertexList:vertices
                                                    voxelData:neighborhood
                                                         minP:chunkMinP];
        }
    }
    
    return vertices;
}

static void applyLightToVertices(size_t numChunkVerts,
                                 GSTerrainVertex * _Nonnull vertsBuffer,
                                 GSTerrainBuffer * _Nonnull sunlight,
                                 vector_float3 minP)
{
    assert(vertsBuffer);
    assert(sunlight);

    for(GLsizei i=0; i<numChunkVerts; ++i)
    {
        GSTerrainVertex *v = &vertsBuffer[i];
        
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
