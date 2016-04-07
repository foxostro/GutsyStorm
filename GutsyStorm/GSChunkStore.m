//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSRay.h"
#import "GSCamera.h"
#import "GSActiveRegion.h"
#import "GSShader.h"
#import "GSChunkStore.h"
#import "GSBoxedVector.h"
#import "GSNeighborhood.h"

#import "GSChunkVAO.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"

#import "GSGrid.h"
#import "GSGridVAO.h"
#import "GSGridGeometry.h"
#import "GSGridSunlight.h"

#import "GSMatrixUtils.h"

#import <OpenGL/gl.h>

#define ARRAY_LEN(a) (sizeof(a)/sizeof(a[0])) // XXX: find a better home for ARRAY_LEN macro


@interface GSChunkStore ()

- (void)createGrids;
- (void)setupGridDependencies;
- (void)setupActiveRegionWithCamera:(nonnull GSCamera *)cam;

+ (nonnull NSURL *)newTerrainCacheFolderURL;
- (nonnull GSNeighborhood *)neighborhoodAtPoint:(vector_float3)p;
- (BOOL)tryToGetNeighborhoodAtPoint:(vector_float3)p neighborhood:(GSNeighborhood * _Nonnull * _Nonnull)neighborhood;

- (nonnull GSChunkGeometryData *)chunkGeometryAtPoint:(vector_float3)p;
- (nonnull GSChunkSunlightData *)chunkSunlightAtPoint:(vector_float3)p;
- (nonnull GSChunkVoxelData *)chunkVoxelsAtPoint:(vector_float3)p;

- (BOOL)tryToGetChunkVoxelsAtPoint:(vector_float3)p chunk:(GSChunkVoxelData * _Nonnull * _Nonnull)chunk;
- (nonnull NSObject <GSGridItem> *)newChunkWithMinimumCorner:(vector_float3)minP;

@end


@implementation GSChunkStore
{
    GSGridVAO *_gridVAO;
    GSGridGeometry *_gridGeometryData;
    GSGridSunlight *_gridSunlightData;
    GSGrid<GSChunkVoxelData *> *_gridVoxelData;

    dispatch_group_t _groupForSaving;
    dispatch_queue_t _chunkTaskQueue;
    dispatch_queue_t _queueForSaving;

    BOOL _chunkStoreHasBeenShutdown;
    GSCamera *_camera;
    NSURL *_folder;
    GSShader *_terrainShader;
    NSOpenGLContext *_glContext;

    GSTerrainProcessorBlock _generator;

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
    assert(!_gridVAO);

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
    
    _gridVAO = [[GSGridVAO alloc] initWithName:@"gridVAO"
                                       factory:^NSObject <GSGridItem> * (vector_float3 minCorner) {
                                           GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:minCorner];
                                           return [[GSChunkVAO alloc] initWithChunkGeometry:geometry
                                                                                  glContext:_glContext];
                                       }];
}

- (nonnull NSSet<GSBoxedVector *> *)sunlightChunksInvalidatedByVoxelChangeAtPoint:(nonnull GSGridEdit *)edit
{
    assert(edit);
    vector_float3 p = edit.pos;

    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    vector_long3 clpOfEdit = GSMakeIntegerVector3(p.x - minP.x, p.y - minP.y, p.z - minP.z);

    // If the change is deep enough into the interior of the block then the change cannot affect the neighbors.
    if (clpOfEdit.x >= CHUNK_LIGHTING_MAX && clpOfEdit.z >= CHUNK_LIGHTING_MAX &&
        clpOfEdit.x < (CHUNK_SIZE_X-CHUNK_LIGHTING_MAX) && clpOfEdit.z < (CHUNK_SIZE_Z-CHUNK_LIGHTING_MAX)) {
        return [NSSet setWithObject:[GSBoxedVector boxedVectorWithVector:minP]];
    }

    GSVoxel originalVoxel = [edit.originalObject voxelAtLocalPosition:clpOfEdit];
    GSVoxel modifiedVoxel = [edit.modifiedObject voxelAtLocalPosition:clpOfEdit];

    BOOL originalIsOpaque = originalVoxel.opaque;
    BOOL modifiedIsOpaque = modifiedVoxel.opaque;
    
    // If the original block was opaque, and the new block is opaque, then the change actually can be resolved by
    // updating sunlight for the one block that was modified, and nothing else.
    // If the original block was not-opaque and the new block is also not-opaque then the change can be resolved as in
    // the above case. Only one sunlight block needs to be updated.
    if (originalIsOpaque == modifiedIsOpaque) {
        return [NSSet setWithObject:[GSBoxedVector boxedVectorWithVector:minP]];
    }
    
    GSTerrainBufferElement m = CHUNK_LIGHTING_MAX;
    
    // If the original block was opaque, and the new block is not-opaque, then the change cannot propagate a further
    // distance than the difference between the the maximum and minimum adjacent light levels. Noting, however, that
    // light levels of opaque blocks must be ignored.
    if (originalIsOpaque && !modifiedIsOpaque) {
        GSTerrainBufferElement maxSunlight = 0, minSunlight = CHUNK_LIGHTING_MAX;
        
        // Is the edit on the border of the chunk? If so then testing the adjacent chunks would involve taking a lock on
        // the neighboring chunks. If that's the case then skip neighbor tests and assume the edit affects the full
        // range. We do this because, upon entering this method, we're already holding a lock on the stripe which
        // contains the chunk which contains the edit. If we attempt to take the lock on another voxel data chunk, and
        // both chunks reside on the same stripe, then taking the lock will cause a deadlock.
        if (clpOfEdit.x > 0 && clpOfEdit.z > 0 && clpOfEdit.x < (CHUNK_SIZE_X-1) && clpOfEdit.z < (CHUNK_SIZE_Z-1)) {
            vector_long3 adjacentPoints[] = {
                clpOfEdit,
                clpOfEdit + GSMakeIntegerVector3(+1,  0,  0),
                clpOfEdit + GSMakeIntegerVector3(-1,  0,  0),
                clpOfEdit + GSMakeIntegerVector3( 0, +1,  0),
                clpOfEdit + GSMakeIntegerVector3( 0, -1,  0),
                clpOfEdit + GSMakeIntegerVector3( 0,  0, +1),
                clpOfEdit + GSMakeIntegerVector3( 0,  0, -1)
            };
            for(size_t i = 0; i < ARRAY_LEN(adjacentPoints); ++i)
            {
                vector_long3 adjacentPoint = adjacentPoints[i];
                
                if (adjacentPoint.y >= 0 && adjacentPoint.y < CHUNK_SIZE_Y) {
                    GSVoxel voxel = [edit.originalObject voxelAtLocalPosition:adjacentPoint];
                    
                    if (!voxel.opaque) {
                        vector_float3 worldPos = vector_make(adjacentPoint.x + minP.x,
                                                             adjacentPoint.y + minP.y,
                                                             adjacentPoint.z + minP.z);
                        GSTerrainBufferElement sunlightLevel = [self sunlightAtPoint:worldPos];
                        maxSunlight = MAX(maxSunlight, sunlightLevel);
                        minSunlight = MIN(minSunlight, sunlightLevel);
                    }
                }
            }
            
            m = maxSunlight - minSunlight;
        }
    } else {
        // If the original block was not-opaque and the new block is opaque then the change CANNOT be resolved by taking
        // a difference as above. In this case, light must be propagated through first in order for the max - min calc
        // to work. So: in this case, assume the change propagates the maximum distance.
    }

    NSArray *points = @[[GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p)],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(+m,  0,  0))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make(-m,  0,  0))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, +m))],
                        [GSBoxedVector boxedVectorWithVector:GSMinCornerForChunkAtPoint(p + vector_make( 0,  0, -m))],
                        ];
    NSSet *set = [NSSet setWithArray:points];
    return set;
}

- (void)setupGridDependencies
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(_gridVoxelData);
    assert(_gridSunlightData);
    assert(_gridGeometryData);

    // Each chunk sunlight object depends on the corresponding neighborhood of voxel data objects.
    [_gridVoxelData registerDependentGrid:_gridSunlightData mapping:^NSSet<GSBoxedVector *> * (GSGridEdit *edit) {
        return [self sunlightChunksInvalidatedByVoxelChangeAtPoint:edit];
    }];

    NSSet<GSBoxedVector *> * (^oneToOne)(GSGridEdit *) = ^NSSet<GSBoxedVector *> * (GSGridEdit *edit) {
        GSBoxedVector *p = [GSBoxedVector boxedVectorWithVector:edit.pos];
        return [NSSet<GSBoxedVector *> setWithObject:p];
    };

    // Each chunk geometry object depends on the single, corresponding chunk sunlight object.
    [_gridSunlightData registerDependentGrid:_gridGeometryData mapping:oneToOne];

    // Each chunk VAO object depends on the single, corresponding chunk geometry object.
    [_gridGeometryData registerDependentGrid:_gridVAO mapping:oneToOne];
}

- (void)setupActiveRegionWithCamera:(nonnull GSCamera *)cam
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(cam);
    assert(_gridVAO);

    // Active region is bounded at y>=0.
    const NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
    _activeRegionExtent = vector_make(w, CHUNK_SIZE_Y, w);
    _activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:_activeRegionExtent
                                                                camera:cam
                                                               vaoGrid:_gridVAO];

    // Whenever a VAO is invalidated, the active region must be invalidated.
    __weak GSActiveRegion *weakActiveRegion = _activeRegion;
    _gridVAO.invalidationNotification = ^{
        [weakActiveRegion notifyOfChangeInActiveRegionVAOs];
    };
}

- (nonnull instancetype)initWithSeed:(NSUInteger)seed
                               camera:(nonnull GSCamera *)cam
                        terrainShader:(nonnull GSShader *)shader
                            glContext:(nonnull NSOpenGLContext *)context
                            generator:(nonnull GSTerrainProcessorBlock)generator
{
    self = [super init];
    if (self) {
        _folder = [GSChunkStore newTerrainCacheFolderURL];
        _groupForSaving = dispatch_group_create();
        _chunkStoreHasBeenShutdown = NO;
        _camera = cam;
        _terrainShader = shader;
        _glContext = context;
        _generator = [generator copy];
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
    assert(_gridVAO);
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

    [_gridVAO evictAllItems];
    _gridVAO = nil;

    _groupForSaving = NULL;
    _chunkTaskQueue = NULL;
    _queueForSaving = NULL;
}

- (void)drawActiveChunks
{
    assert(_terrainShader);
    assert(_activeRegion);

    matrix_float4x4 translation = GSMatrixFromTranslation(vector_make(0.5f, 0.5f, 0.5f));
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
    [_activeRegion updateVAOsInCameraFrustum];
}

- (BOOL)tryToGetVoxelAtPoint:(vector_float3)pos voxel:(nonnull GSVoxel *)voxel
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

- (GSTerrainBufferElement)sunlightAtPoint:(vector_float3)pos
{
    assert(!_chunkStoreHasBeenShutdown);
    GSChunkSunlightData *chunk = [self chunkSunlightAtPoint:pos];
    assert(chunk);
    return [chunk.sunlight valueAtPosition:GSMakeIntegerVector3(pos.x-chunk.minP.x,
                                                                pos.y-chunk.minP.y,
                                                                pos.z-chunk.minP.z)];
}

- (BOOL)enumerateVoxelsOnRay:(GSRay)ray
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

- (nonnull GSNeighborhood *)neighborhoodAtPoint:(vector_float3)p
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
                       neighborhood:(GSNeighborhood * _Nonnull * _Nonnull)outNeighborhood
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

- (nonnull GSChunkGeometryData *)chunkGeometryAtPoint:(vector_float3)p
{
    if (_chunkStoreHasBeenShutdown) {
        @throw nil;
    }
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridGeometryData);
    return [_gridGeometryData objectAtPoint:p];
}

- (nonnull GSChunkSunlightData *)chunkSunlightAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridSunlightData);
    return [_gridSunlightData objectAtPoint:p];
}

- (nonnull GSChunkVoxelData *)chunkVoxelsAtPoint:(vector_float3)p
{
    assert(!_chunkStoreHasBeenShutdown);
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(_gridVoxelData);
    return [_gridVoxelData objectAtPoint:p];
}

- (BOOL)tryToGetChunkVoxelsAtPoint:(vector_float3)p chunk:(GSChunkVoxelData * _Nonnull * _Nonnull)chunk
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

+ (nonnull NSURL *)newTerrainCacheFolderURL
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

- (nonnull NSObject <GSGridItem> *)newChunkWithMinimumCorner:(vector_float3)minP
{
    assert(!_chunkStoreHasBeenShutdown);

    return [[GSChunkVoxelData alloc] initWithMinP:minP
                                           folder:_folder
                                   groupForSaving:_groupForSaving
                                   queueForSaving:_queueForSaving
                                   chunkTaskQueue:_chunkTaskQueue
                                        generator:_generator];
}

- (void)purge
{
    if (!_chunkStoreHasBeenShutdown) {
        assert(_gridVoxelData);
        assert(_gridGeometryData);
        assert(_gridSunlightData);
        assert(_gridVAO);

        [_gridVoxelData evictAllItems];
        [_gridGeometryData evictAllItems];
        [_gridSunlightData evictAllItems];
        [_gridVAO evictAllItems];
    }
}

@end