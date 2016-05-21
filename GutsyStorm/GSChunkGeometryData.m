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
#import "GSVoxelNeighborhood.h"
#import "SyscallWrappers.h"
#import "GSActivity.h"
#import "GSErrorCodes.h"
#import "GSTerrainGeometryGenerator.h"


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
                              folder:(nullable NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
                        allowLoading:(BOOL)allowLoading
{
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
        NSURL *url = folder ? [NSURL URLWithString:fileName relativeToURL:folder] : nil;
        NSError *error = nil;
        
        if (url && allowLoading) {
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
            GSVoxel *voxels = [sunlight.neighborhood newVoxelBufferReturningCount:NULL];
            GSIntAABB voxelBox = { .mins = GSCombinedMinP, .maxs = GSCombinedMaxP };

            for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
            {
                GSTerrainGeometry *geometry = GSTerrainGeometryCreate();
                GSTerrainGeometryGenerate(geometry, voxels, voxelBox, sunlight, minCorner, i);
                _vertices[i] = geometry;
            }

            free(voxels);
            GSStopwatchTraceStep(@"Done generating triangles.");

            [self generateDataWithSunlight:sunlight minP:minP];
            if (url) {
                [self saveData:_data url:url queue:queueForSaving group:groupForSaving];
            }
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
                              folder:(nullable NSURL *)folder
                            sunlight:(nonnull GSChunkSunlightData *)sunlight
                            vertices:(GSTerrainGeometry * _Nonnull [GSNumGeometrySubChunks])vertices
                      groupForSaving:(nonnull dispatch_group_t)groupForSaving
                      queueForSaving:(nonnull dispatch_queue_t)queueForSaving
{
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
            _vertices[i] = GSTerrainGeometryCopy(vertices[i]);
        }
        
        NSString *fileName = [[self class] fileNameForGeometryDataFromMinP:minCorner];
        NSURL *url = folder ? [NSURL URLWithString:fileName relativeToURL:folder] : nil;
        
        [self generateDataWithSunlight:sunlight minP:minP];

        if (url) {
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

- (nonnull instancetype)copyWithZone:(nullable NSZone *)zone
{
    return self; // all geometry objects are immutable, so return self instead of deep copying
}

- (void)dealloc
{
    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        GSTerrainGeometryDestroy(_vertices[i]);
    }
}

- (nonnull instancetype)copyWithSunlight:(nonnull GSChunkSunlightData *)sunlight
                       invalidatedRegion:(GSIntAABB)invalidatedRegion
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
        GSFloatAABB a = {
            .mins = vector_float(invalidatedRegion.mins) + minP,
            .maxs = vector_float(invalidatedRegion.maxs) + minP
        };

        for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
        {
            GSFloatAABB b = GSTerrainGeometrySubchunkBoxFloat(minP, i);
            invalidatedSubChunk[i] = GSFloatAABBIntersects(a, b);
        }
    }

    GSVoxel *voxels = [sunlight.neighborhood newVoxelBufferReturningCount:NULL];
    GSIntAABB voxelBox = { .mins = GSCombinedMinP, .maxs = GSCombinedMaxP };
    GSTerrainGeometry *updatedVertices[GSNumGeometrySubChunks] = {NULL};

    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        GSTerrainGeometry *vertices;

        // Regenerate vertices for the sub-chunk if we determined they have been invalidated, and also if we don't have
        // any vertices recorded for the sub-chunk at all.
        if (invalidatedSubChunk[i] || (!_vertices[i])) {
            GSTerrainGeometry *geometry = GSTerrainGeometryCreate();
            GSTerrainGeometryGenerate(geometry, voxels, voxelBox, sunlight, minP, i);
            vertices = geometry;
        } else {
            vertices = GSTerrainGeometryCopy(_vertices[i]);
        }

        updatedVertices[i] = vertices;
    }

    free(voxels);

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

- (nonnull GSTerrainVertex *)copyVertsReturningCount:(nonnull GLsizei *)outCount
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

    GSTerrainVertex *vertsCopy = malloc(count * sizeof(GSTerrainVertex));
    if(!vertsCopy) {
        [NSException raise:NSMallocException format:@"Out of memory allocating vertsCopy in -copyVertsToBuffer:."];
    }
    
    memcpy(vertsCopy, vertsBuffer, count * sizeof(GSTerrainVertex));

    *outCount = count;
    return vertsCopy;
}

- (void)generateDataWithSunlight:(nonnull GSChunkSunlightData *)sunlight minP:(vector_float3)minCorner
{
    NSParameterAssert(sunlight);
    
    GLsizei numChunkVerts = 0;
    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        numChunkVerts += _vertices[i]->count;
    }

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
    GLsizei vertIdx = 0;
    for(NSUInteger i=0; i<GSNumGeometrySubChunks; ++i)
    {
        size_t count = _vertices[i]->count;
        if (count > 0) {
            assert(vertIdx < numChunkVerts);
            memcpy(&vertsBuffer[vertIdx], _vertices[i]->vertices, sizeof(GSTerrainVertex) * count);
            vertIdx += count;
        }
    }
    
    _data = data;
}

- (void)saveData:(nonnull NSData *)data
             url:(nonnull NSURL *)url
           queue:(nonnull dispatch_queue_t)queue
           group:(nonnull dispatch_group_t)group
{
    NSParameterAssert(data);
    NSParameterAssert(url);
    NSParameterAssert(queue);
    NSParameterAssert(group);

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