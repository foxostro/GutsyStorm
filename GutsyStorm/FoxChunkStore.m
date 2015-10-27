//
//  FoxChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxIntegerVector3.h"
#import "FoxRay.h"
#import "GSCamera.h"
#import "GSActiveRegion.h"
#import "FoxShader.h"
#import "FoxChunkStore.h"
#import "FoxBoxedVector.h"
#import "GSNeighborhood.h"

#import "GSChunkVBOs.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"

#import "GSGrid.h"
#import "GSGridVBOs.h"
#import "GSGridGeometry.h"
#import "GSGridSunlight.h"

#import "FoxMatrixUtils.h"


@interface FoxChunkStore ()

- (void)createGrids;
- (void)setupGridDependencies;
- (void)setupActiveRegionWithCamera:(GSCamera *)cam;

+ (NSURL *)newTerrainCacheFolderURL;
- (GSNeighborhood *)neighborhoodAtPoint:(vector_float3)p;
- (BOOL)tryToGetNeighborhoodAtPoint:(vector_float3)p neighborhood:(GSNeighborhood **)neighborhood;

- (GSChunkGeometryData *)chunkGeometryAtPoint:(vector_float3)p;
- (GSChunkSunlightData *)chunkSunlightAtPoint:(vector_float3)p;
- (GSChunkVoxelData *)chunkVoxelsAtPoint:(vector_float3)p;

- (BOOL)tryToGetChunkVoxelsAtPoint:(vector_float3)p chunk:(GSChunkVoxelData **)chunk;
- (NSObject <GSGridItem> *)newChunkWithMinimumCorner:(vector_float3)minP;

@end


@implementation FoxChunkStore
{
    GSGridVBOs *_gridVBOs;
    GSGridGeometry *_gridGeometryData;
    GSGridSunlight *_gridSunlightData;
    GSGrid<GSChunkVoxelData *> *_gridVoxelData;

    dispatch_group_t _groupForSaving;
    dispatch_queue_t _chunkTaskQueue;
    dispatch_queue_t _queueForSaving;

    BOOL _chunkStoreHasBeenShutdown;
    GSCamera *_camera;
    NSURL *_folder;
    FoxShader *_terrainShader;
    NSOpenGLContext *_glContext;

    terrain_generator_t _generator;
    terrain_post_processor_t _postProcessor;

    GSActiveRegion *_activeRegion;
    vector_float3 _activeRegionExtent; // The active region is specified relative to the camera position.
}

+ (void)initialize
{
    NSDictionary<NSString *, id> *values = @{ @"ActiveRegionExtent": @"256" };
    [[NSUserDefaults standardUserDefaults] registerDefaults:values];
}

- (void)createGrids
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(!_gridVoxelData);
    assert(!_gridSunlightData);
    assert(!_gridVBOs);

    _gridVoxelData = [[GSGrid alloc] initWithName:@"gridVoxelData"
                                          factory:^NSObject <GSGridItem> * (vector_float3 minCorner) {
                                              return [self newChunkWithMinimumCorner:minCorner];
                                          }];

    _gridSunlightData = [[GSGridSunlight alloc]
                         initWithName:@"gridSunlightData"
                          cacheFolder:_folder
                              factory:^NSObject <GSGridItem> * (vector_float3 minCorner) {
                             GSNeighborhood *neighborhood = [self neighborhoodAtPoint:minCorner];
                             return [[GSChunkSunlightData alloc] initWithMinP:minCorner
                                                                       folder:_folder
                                                               groupForSaving:_groupForSaving
                                                               queueForSaving:_queueForSaving
                                                               chunkTaskQueue:_chunkTaskQueue
                                                                 neighborhood:neighborhood];
                         }];

    _gridGeometryData = [[GSGridGeometry alloc]
                         initWithName:@"gridGeometryData"
                          cacheFolder:_folder
                              factory:^NSObject <GSGridItem> * (vector_float3 minCorner) {
                                  GSChunkSunlightData *sunlight = [self chunkSunlightAtPoint:minCorner];
                                  return [[GSChunkGeometryData alloc] initWithMinP:minCorner
                                                                       folder:_folder
                                                                     sunlight:sunlight];
                              }];
    
    _gridVBOs = [[GSGridVBOs alloc] initWithName:@"gridVBOs"
                                         factory:^NSObject <GSGridItem> * (vector_float3 minCorner) {
                                             GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:minCorner];
                                             NSObject <GSGridItem> *vbo;
                                             vbo = [[GSChunkVBOs alloc] initWithChunkGeometry:geometry
                                                                                    glContext:_glContext];
                                             return vbo;
                                         }];
}

- (NSSet<FoxBoxedVector *> *)sunlightChunksInvalidatedByVoxelChangeAtPoint:(GSGridEdit *)edit
{
    assert(edit);
    vector_float3 p = edit.pos;
    BOOL fullRebuild = YES;
    GSVoxel voxel;

    {
        GSChunkVoxelData *voxelChunk = edit.originalObject;
        vector_float3 minP = voxelChunk.minP;
        vector_long3 chunkLocalPos = GSMakeIntegerVector3(p.x-minP.x, p.y-minP.y+1, p.z-minP.z);
        voxel = [voxelChunk voxelAtLocalPosition:chunkLocalPos];
    }

    if (!voxel.outside) {
        fullRebuild = NO;
    }

    if (fullRebuild) {
        NSMutableArray<FoxBoxedVector *> *correspondingPoints =
            [[NSMutableArray<FoxBoxedVector *> alloc] initWithCapacity:CHUNK_NUM_NEIGHBORS];
        for(GSVoxelNeighborIndex i=0; i<CHUNK_NUM_NEIGHBORS; ++i)
        {
            vector_float3 offset = [GSNeighborhood offsetForNeighborIndex:i];
            FoxBoxedVector *boxedPoint = [FoxBoxedVector boxedVectorWithVector:(p + offset)];
            [correspondingPoints addObject:boxedPoint];
        }
        return [NSSet<FoxBoxedVector *> setWithArray:correspondingPoints];
    } else {
        /* If the modified block is below an Inside block then changes to it can only affect lighting for blocks at most
         * CHUNK_LIGHTING_MAX steps away, but even this is too generous for many changes. To precisely determine the
         * range of the lighting change, take the light levels of all blocks directly adjacent to the one that was
         * modified. In the case where a block is being added, the brightest adjacent block was flooding over the space
         * and now will no longer do that. The range of the change is determined by the difference between the lighting
         * levels of the brightest and the dimmest adjacent blocks. Ditto the case where a block is being removed.
         */
        // XXX: Do the precise change range computation described above.
        const unsigned m = CHUNK_LIGHTING_MAX;
        NSMutableSet<FoxBoxedVector *> *set = [NSMutableSet<FoxBoxedVector *> new];
        [set addObjectsFromArray:@[[FoxBoxedVector boxedVectorWithVector:p],
                                   [FoxBoxedVector boxedVectorWithVector:(p + vector_make(+m,  0,  0))],
                                   [FoxBoxedVector boxedVectorWithVector:(p + vector_make(-m,  0,  0))],
                                   [FoxBoxedVector boxedVectorWithVector:(p + vector_make( 0, -m,  0))],
                                   [FoxBoxedVector boxedVectorWithVector:(p + vector_make( 0,  0, +m))],
                                   [FoxBoxedVector boxedVectorWithVector:(p + vector_make( 0,  0, -m))],
                                   ]];
        return set;
    }
}

- (void)setupGridDependencies
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridVoxelData);
    assert(_gridSunlightData);
    assert(_gridGeometryData);

    // Each chunk sunlight object depends on the corresponding neighborhood of voxel data objects.
    [_gridVoxelData registerDependentGrid:_gridSunlightData mapping:^NSSet<FoxBoxedVector *> * (GSGridEdit *edit) {
        return [self sunlightChunksInvalidatedByVoxelChangeAtPoint:edit];
    }];

    NSSet<FoxBoxedVector *> * (^oneToOne)(GSGridEdit *) = ^NSSet<FoxBoxedVector *> * (GSGridEdit *edit) {
        FoxBoxedVector *p = [FoxBoxedVector boxedVectorWithVector:edit.pos];
        return [NSSet<FoxBoxedVector *> setWithObject:p];
    };

    // Each chunk geometry object depends on the single, corresponding chunk sunlight object.
    [_gridSunlightData registerDependentGrid:_gridGeometryData mapping:oneToOne];

    // Each chunk VBO object depends on the single, corresponding chunk geometry object.
    [_gridGeometryData registerDependentGrid:_gridVBOs mapping:oneToOne];
}

- (void)setupActiveRegionWithCamera:(GSCamera *)cam
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(cam);
    assert(_gridVBOs);

    // Active region is bounded at y>=0.
    const NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
    _activeRegionExtent = vector_make(w, CHUNK_SIZE_Y, w);
    _activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:_activeRegionExtent
                                                                camera:cam
                                                               vboGrid:_gridVBOs];

    // Whenever a VBO is invalidated, the active region must be invalidated.
    __weak GSActiveRegion *weakActiveRegion = _activeRegion;
    _gridVBOs.invalidationNotification = ^{
        [weakActiveRegion notifyOfChangeInActiveRegionVBOs];
    };
}

- (instancetype)initWithSeed:(NSUInteger)seed
                      camera:(GSCamera *)cam
               terrainShader:(FoxShader *)shader
                   glContext:(NSOpenGLContext *)context
                   generator:(terrain_generator_t)generatorCallback
               postProcessor:(terrain_post_processor_t)postProcessorCallback
{
    self = [super init];
    if (self) {
        _folder = [FoxChunkStore newTerrainCacheFolderURL];
        _groupForSaving = dispatch_group_create();
        _chunkStoreHasBeenShutdown = NO;
        _camera = cam;
        _terrainShader = shader;
        _glContext = context;
        _generator = [generatorCallback copy];
        _postProcessor = [postProcessorCallback copy];
        _chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        _queueForSaving = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        [self createGrids];
        [self setupGridDependencies];
        [self setupActiveRegionWithCamera:cam];
    }
    
    return self;
}

- (void)shutdown
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridVoxelData);
    assert(_gridSunlightData);
    assert(_gridGeometryData);
    assert(_gridVBOs);
    assert(_groupForSaving);
    assert(_chunkTaskQueue);
    assert(_queueForSaving);
    
    // Shutdown the active region, which maintains it's own queue of async updates.
    [_activeRegion shutdown];
    _activeRegion = nil;

    // Wait for save operations to complete.
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(_groupForSaving, DISPATCH_TIME_FOREVER);
    NSLog(@"All chunks have been saved.");
    
    // From this point on, we do not expect anyone to access the chunk store data.
    _chunkStoreHasBeenShutdown = YES;
    
    [_gridVoxelData evictAllItems];
    _gridVoxelData = nil;

    [_gridSunlightData evictAllItems];
    _gridSunlightData = nil;

    [_gridGeometryData evictAllItems];
    _gridGeometryData = nil;

    [_gridVBOs evictAllItems];
    _gridVBOs = nil;

    _groupForSaving = NULL;
    _chunkTaskQueue = NULL;
    _queueForSaving = NULL;
}

- (void)drawActiveChunks
{
    assert(_terrainShader);
    assert(_activeRegion);

    matrix_float4x4 translation = matrix_from_translation(vector_make(0.5f, 0.5f, 0.5f));
    matrix_float4x4 modelView = matrix_multiply(translation, _camera.modelViewMatrix);
    matrix_float4x4 mvp = matrix_multiply(modelView, _camera.projectionMatrix);

    [_terrainShader bind];
    [_terrainShader bindUniformWithMatrix4x4:mvp name:@"mvp"];

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);

    [_activeRegion draw];

    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);

    [_terrainShader unbind];
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_activeRegion);
    [_activeRegion updateWithCameraModifiedFlags:flags];
}

- (void)placeBlockAtPoint:(vector_float3)pos block:(GSVoxel)block
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridVoxelData);
    assert(_activeRegion);

    [_gridVoxelData replaceItemAtPoint:pos transform:^NSObject<GSGridItem> *(NSObject<GSGridItem> *originalItem) {
        GSChunkVoxelData *modifiedItem = [((GSChunkVoxelData *)originalItem) copyWithEditAtPoint:pos block:block];
        [modifiedItem saveToFile];
        return modifiedItem;
    }];

    // Must notify the active region so that the change will get picked up right away.
    [_activeRegion updateVBOsInCameraFrustum];
}

- (BOOL)tryToGetVoxelAtPoint:(vector_float3)pos voxel:(GSVoxel *)voxel
{
    GSChunkVoxelData *chunk = nil;

    assert(!_chunkStoreHasBeenShutdown);
    assert(voxel);

    if(![self tryToGetChunkVoxelsAtPoint:pos chunk:&chunk]) {
        return NO;
    }

    assert(chunk);

    *voxel = [chunk voxelAtLocalPosition:GSMakeIntegerVector3(pos.x-chunk.minP.x,
                                                               pos.y-chunk.minP.y,
                                                               pos.z-chunk.minP.z)];
    
    return YES;
}

- (GSVoxel)voxelAtPoint:(vector_float3)pos
{
    assert(!_chunkStoreHasBeenShutdown);

    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];

    assert(chunk);

    return [chunk voxelAtLocalPosition:GSMakeIntegerVector3(pos.x-chunk.minP.x,
                                                             pos.y-chunk.minP.y,
                                                             pos.z-chunk.minP.z)];
}

- (BOOL)enumerateVoxelsOnRay:(struct fox_ray)ray
                    maxDepth:(unsigned)maxDepth
                   withBlock:(void (^ _Nonnull)(vector_float3 p, BOOL * _Nonnull stop, BOOL * _Nonnull fail))block
{
    assert(!_chunkStoreHasBeenShutdown);

    /* Implementation is based on:
     * "A Fast Voxel Traversal Algorithm for Ray Tracing"
     * John Amanatides, Andrew Woo
     * http://www.cse.yorku.ca/~amana/research/grid.pdf
     *
     * See also: http://www.xnawiki.com/index.php?title=Voxel_traversal
     */
    
    // NOTES:
    // * This code assumes that the ray's position and direction are in 'cell coordinates', which means
    //   that one unit equals one cell in all directions.
    // * When the ray doesn't start within the voxel grid, calculate the first position at which the
    //   ray could enter the grid. If it never enters the grid, there is nothing more to do here.
    // * Also, it is important to test when the ray exits the voxel grid when the grid isn't infinite.
    // * The Point3D structure is a simple structure having three integer fields (X, Y and Z).
    
    // The cell in which the ray starts.
    vector_long3 start = GSMakeIntegerVector3(floorf(ray.origin.x), floorf(ray.origin.y), floorf(ray.origin.z));
    int x = (int)start.x;
    int y = (int)start.y;
    int z = (int)start.z;
    
    // Determine which way we go.
    int stepX = (ray.direction.x<0) ? -1 : (ray.direction.x==0) ? 0 : +1;
    int stepY = (ray.direction.y<0) ? -1 : (ray.direction.y==0) ? 0 : +1;
    int stepZ = (ray.direction.z<0) ? -1 : (ray.direction.z==0) ? 0 : +1;
    
    // Calculate cell boundaries. When the step (i.e. direction sign) is positive,
    // the next boundary is AFTER our current position, meaning that we have to add 1.
    // Otherwise, it is BEFORE our current position, in which case we add nothing.
    vector_long3 cellBoundary = GSMakeIntegerVector3(x + (stepX > 0 ? 1 : 0),
                                                          y + (stepY > 0 ? 1 : 0),
                                                          z + (stepZ > 0 ? 1 : 0));
    
    // NOTE: For the following calculations, the result will be Single.PositiveInfinity
    // when ray.Direction.X, Y or Z equals zero, which is OK. However, when the left-hand
    // value of the division also equals zero, the result is Single.NaN, which is not OK.
    
    // Determine how far we can travel along the ray before we hit a voxel boundary.
    vector_float3 tMax = vector_make((cellBoundary.x - ray.origin.x) / ray.direction.x,    // Boundary is a plane on the YZ axis.
                                    (cellBoundary.y - ray.origin.y) / ray.direction.y,    // Boundary is a plane on the XZ axis.
                                    (cellBoundary.z - ray.origin.z) / ray.direction.z);   // Boundary is a plane on the XY axis.
    if(isnan(tMax.x)) { tMax.x = +INFINITY; }
    if(isnan(tMax.y)) { tMax.y = +INFINITY; }
    if(isnan(tMax.z)) { tMax.z = +INFINITY; }

    // Determine how far we must travel along the ray before we have crossed a gridcell.
    vector_float3 tDelta = vector_make(stepX / ray.direction.x,                    // Crossing the width of a cell.
                                      stepY / ray.direction.y,                    // Crossing the height of a cell.
                                      stepZ / ray.direction.z);                   // Crossing the depth of a cell.
    if(isnan(tDelta.x)) { tDelta.x = +INFINITY; }
    if(isnan(tDelta.y)) { tDelta.y = +INFINITY; }
    if(isnan(tDelta.z)) { tDelta.z = +INFINITY; }
    
    // For each step, determine which distance to the next voxel boundary is lowest (i.e.
    // which voxel boundary is nearest) and walk that way.
    for(int i = 0; i < maxDepth; i++)
    {
        if(y >= _activeRegionExtent.y || y < 0) {
            return YES; // The vertical extent of the world is limited.
        }
        
        BOOL stop = NO;
        BOOL fail = NO;
        block(vector_make(x, y, z), &stop, &fail);

        if(fail) {
            return NO; // the block was going to block so it stopped and called for an abort
        }

        if(stop) {
            return YES;
        }
        
        // Do the next step.
        if (tMax.x < tMax.y && tMax.x < tMax.z) {
            // tMax.X is the lowest, an YZ cell boundary plane is nearest.
            x += stepX;
            tMax.x += tDelta.x;
        } else if (tMax.y < tMax.z) {
            // tMax.Y is the lowest, an XZ cell boundary plane is nearest.
            y += stepY;
            tMax.y += tDelta.y;
        } else {
            // tMax.Z is the lowest, an XY cell boundary plane is nearest.
            z += stepZ;
            tMax.z += tDelta.z;
        }
    }

    return YES;
}

- (GSNeighborhood *)neighborhoodAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);

    GSNeighborhood *neighborhood = [[GSNeighborhood alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 a = p + [GSNeighborhood offsetForNeighborIndex:i];
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:a]; // NOTE: may block
        assert(voxels);
        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }
    
    return neighborhood;
}

- (BOOL)tryToGetNeighborhoodAtPoint:(vector_float3)p
                       neighborhood:(GSNeighborhood **)outNeighborhood
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(outNeighborhood);

    GSNeighborhood *neighborhood = [[GSNeighborhood alloc] init];

    for(GSVoxelNeighborIndex i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        vector_float3 a = p + [GSNeighborhood offsetForNeighborIndex:i];
        GSChunkVoxelData *voxels = nil;

        if(![self tryToGetChunkVoxelsAtPoint:a chunk:&voxels]) {
            return NO;
        }

        assert(voxels);

        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }

    *outNeighborhood = neighborhood;
    return YES;
}

- (GSChunkGeometryData *)chunkGeometryAtPoint:(vector_float3)p
{
    if (_chunkStoreHasBeenShutdown) {
        @throw nil;
    }
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridGeometryData);
    return [_gridGeometryData objectAtPoint:p];
}

- (GSChunkSunlightData *)chunkSunlightAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridSunlightData);
    return [_gridSunlightData objectAtPoint:p];
}

- (GSChunkVoxelData *)chunkVoxelsAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridVoxelData);
    return [_gridVoxelData objectAtPoint:p];
}

- (BOOL)tryToGetChunkVoxelsAtPoint:(vector_float3)p chunk:(GSChunkVoxelData **)chunk
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(chunk);
    assert(_gridVoxelData);

    GSChunkVoxelData *v = nil;
    BOOL success = [_gridVoxelData objectAtPoint:p
                                        blocking:NO
                                          object:&v
                                 createIfMissing:YES
                                   didCreateItem:nil];

    if(success) {
        *chunk = v;
    }

    return success;
}

+ (NSURL *)newTerrainCacheFolderURL
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    NSString *bundleIdentifier = [[NSRunningApplication currentApplication] bundleIdentifier];

    folder = [folder stringByAppendingPathComponent:bundleIdentifier];
    folder = [folder stringByAppendingPathComponent:@"terrain-cache"];
    NSLog(@"ChunkStore will cache terrain data in folder: %@", folder);
    
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        NSLog(@"Failed to create terrain cache folder: %@", folder);
    }
    
    NSURL *url = [[NSURL alloc] initFileURLWithPath:folder isDirectory:YES];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSLog(@"ChunkStore's terrain cache folder is not reachable: %@", folder);
    }
    
    return url;
}

- (NSObject <GSGridItem> *)newChunkWithMinimumCorner:(vector_float3)minP
{
    assert(!_chunkStoreHasBeenShutdown);

    return [[GSChunkVoxelData alloc] initWithMinP:minP
                                           folder:_folder
                                   groupForSaving:_groupForSaving
                                   queueForSaving:_queueForSaving
                                   chunkTaskQueue:_chunkTaskQueue
                                        generator:_generator
                                    postProcessor:_postProcessor];
}

- (void)purge
{
    if (!_chunkStoreHasBeenShutdown) {
        assert(_gridVoxelData);
        assert(_gridGeometryData);
        assert(_gridSunlightData);
        assert(_gridVBOs);

        [_gridVoxelData evictAllItems];
        [_gridGeometryData evictAllItems];
        [_gridSunlightData evictAllItems];
        [_gridVBOs evictAllItems];
    }
}

@end