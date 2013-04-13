//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSIntegerVector3.h"
#import "GSRay.h"
#import "GSCamera.h"
#import "GSActiveRegion.h"
#import "GSShader.h"
#import "GSChunkStore.h"
#import "GSBoxedVector.h"
#import "GSNeighborhood.h"

#import "GSChunkVBOs.h"
#import "GSChunkGeometryData.h"
#import "GSChunkSunlightData.h"
#import "GSChunkVoxelData.h"

#import "GSGrid.h"
#import "GSGridVBOs.h"
#import "GSGridGeometry.h"
#import "GSGridSunlight.h"


static dispatch_source_t createDispatchTimer(uint64_t interval, uint64_t leeway, void (^eventHandler)());


@interface GSChunkStore ()

- (void)createGrids;
- (void)setupGridDependencies;
- (void)setupActiveRegionWithCamera:(GSCamera *)cam;

+ (NSURL *)newTerrainCacheFolderURL;
- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p;

- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p;
- (GSChunkSunlightData *)chunkSunlightAtPoint:(GLKVector3)p;
- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p;

- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk;
- (id)newChunkWithMinimumCorner:(GLKVector3)minP;

@end


@implementation GSChunkStore
{
    GSGridVBOs *_gridVBOs;
    GSGridGeometry *_gridGeometryData;
    GSGridSunlight *_gridSunlightData;
    GSGrid *_gridVoxelData;

    dispatch_group_t _groupForSaving;
    dispatch_queue_t _chunkTaskQueue;
    dispatch_queue_t _queueForSaving;

    BOOL _shutdownDrawing;
    dispatch_semaphore_t _semaDrawingIsShutdown;

    dispatch_source_t _timer;

    NSUInteger _numVBOGenerationsAllowedPerFrame;
    GSCamera *_camera;
    NSURL *_folder;
    GSShader *_terrainShader;
    NSOpenGLContext *_glContext;

    terrain_generator_t _generator;
    terrain_post_processor_t _postProcessor;

    GSActiveRegion *_activeRegion;
    GLKVector3 _activeRegionExtent; // The active region is specified relative to the camera position.
}

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if(![defaults objectForKey:@"ActiveRegionExtent"]) {
        NSDictionary *values = @{@"ActiveRegionExtent": @"256"};
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    if(![defaults objectForKey:@"NumVBOGenerationsAllowedPerFrame"]) {
        NSDictionary *values = @{@"NumVBOGenerationsAllowedPerFrame": @"64"};
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)createGrids
{
    _gridVoxelData = [[GSGrid alloc] initWithFactory:^NSObject <GSGridItem> * (GLKVector3 minCorner) {
        return [self newChunkWithMinimumCorner:minCorner];
    }];
    
    _gridSunlightData = [[GSGridSunlight alloc]
                         initWithCacheFolder:_folder
                         factory:^NSObject <GSGridItem> * (GLKVector3 minCorner) {
                             GSNeighborhood *neighborhood = [self neighborhoodAtPoint:minCorner];
                             return [[GSChunkSunlightData alloc] initWithMinP:minCorner
                                                                       folder:_folder
                                                               groupForSaving:_groupForSaving
                                                               queueForSaving:_queueForSaving
                                                               chunkTaskQueue:_chunkTaskQueue
                                                                 neighborhood:neighborhood];
                         }];
    
    _gridGeometryData = [[GSGridGeometry alloc]
                         initWithCacheFolder:_folder
                         factory:^NSObject <GSGridItem> * (GLKVector3 minCorner) {
                             GSChunkSunlightData *sunlight = [self chunkSunlightAtPoint:minCorner];
                             return [[GSChunkGeometryData alloc] initWithMinP:minCorner
                                                                       folder:_folder
                                                                     sunlight:sunlight];
                         }];
    
    _gridVBOs = [[GSGridVBOs alloc] initWithFactory:^NSObject <GSGridItem> * (GLKVector3 minCorner) {
        GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:minCorner];
        return [[GSChunkVBOs alloc] initWithChunkGeometry:geometry glContext:_glContext];
    }];
}

- (void)setupGridDependencies
{
    // Each chunk sunlight object depends on the corresponding neighborhood of voxel data objects.
    [_gridVoxelData registerDependentGrid:_gridSunlightData mapping:^NSSet *(GLKVector3 point) {
        const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+1, +1, +1);
        const ssize_t capacity = (b.x-a.x) * (b.y-a.y) * (b.z-a.z);
        NSMutableArray *correspondingPoint = [[NSMutableArray alloc] initWithCapacity:capacity];
        GSIntegerVector3 positionInNeighborhood;
        FOR_BOX(positionInNeighborhood, a, b)
        {
            GLKVector3 offset = GLKVector3Make(positionInNeighborhood.x, positionInNeighborhood.y, positionInNeighborhood.z);
            GSBoxedVector *boxedPoint = [GSBoxedVector boxedVectorWithVector:GLKVector3Add(point, offset)];
            [correspondingPoint addObject:boxedPoint];
        }
        return [[NSSet alloc] initWithArray:correspondingPoint];
    }];
    
    // Each chunk geometry object depends on the single, corresponding chunk sunlight object.
    [_gridSunlightData registerDependentGrid:_gridGeometryData mapping:^NSSet *(GLKVector3 p) {
        GSBoxedVector *boxedPoint = [GSBoxedVector boxedVectorWithVector:p];
        return [[NSSet alloc] initWithArray:@[boxedPoint]];
    }];
    
    // Each chunk VBO object depends on the single, corresponding chunk geometry object.
    [_gridGeometryData registerDependentGrid:_gridVBOs mapping:^NSSet *(GLKVector3 p) {
        GSBoxedVector *boxedPoint = [GSBoxedVector boxedVectorWithVector:p];
        return [[NSSet alloc] initWithArray:@[boxedPoint]];
    }];
}

- (void)setupActiveRegionWithCamera:(GSCamera *)cam
{
    // Active region is bounded at y>=0.
    const NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
    _activeRegionExtent = GLKVector3Make(w, w, w);
    _activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:_activeRegionExtent
                                                                camera:cam
                                                           vboProducer:^GSChunkVBOs *(GLKVector3 p) {
                                                               assert(p.y >= 0 && p.y < _activeRegionExtent.y);
                                                               return [_gridVBOs objectAtPoint:p];
                                                           }];

    // Whenever a VBO is invalidated, the active region must be invalidated.
    __weak GSActiveRegion *weakActiveRegion = _activeRegion;
    _gridVBOs.invalidationNotification = ^{
        [weakActiveRegion notifyOfChangeInActiveRegionVBOs];
    };
}

- (id)initWithSeed:(NSUInteger)seed
            camera:(GSCamera *)cam
       terrainShader:(GSShader *)shader
           glContext:(NSOpenGLContext *)context
           generator:(terrain_generator_t)generatorCallback
       postProcessor:(terrain_post_processor_t)postProcessorCallback
{
    self = [super init];
    if (self) {
        _folder = [GSChunkStore newTerrainCacheFolderURL];
        _groupForSaving = dispatch_group_create();
        _shutdownDrawing = NO;
        _semaDrawingIsShutdown = dispatch_semaphore_create(0);
        _camera = cam;
        _terrainShader = shader;
        _glContext = context;
        _generator = [generatorCallback copy];
        _postProcessor = [postProcessorCallback copy];
        
        _chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        dispatch_retain(_chunkTaskQueue);

        _queueForSaving = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_retain(_queueForSaving);
        
        [self createGrids];
        [self setupGridDependencies];
        [self setupActiveRegionWithCamera:cam];

        _timer = createDispatchTimer(60 * NSEC_PER_SEC, // interval
                                     NSEC_PER_SEC,     // leeway
                                     ^{
                                         [self purge];
                                         NSLog(@"automatic purge");
                                     });
    }
    
    return self;
}

- (void)shutdown
{
    dispatch_source_cancel(_timer);
    dispatch_release(_timer);

    // Shutdown drawing on the display link thread.
    _shutdownDrawing = YES;
    dispatch_semaphore_wait(_semaDrawingIsShutdown, DISPATCH_TIME_FOREVER);

    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(_groupForSaving, DISPATCH_TIME_FOREVER); // wait for save operations to complete
    NSLog(@"All chunks have been saved.");
    
    [_gridVoxelData evictAllItems];
    _gridVoxelData = nil;

    [_gridSunlightData evictAllItems];
    _gridSunlightData = nil;

    [_gridGeometryData evictAllItems];
    _gridGeometryData = nil;

    [_gridVBOs evictAllItems];
    _gridVBOs = nil;
    
    [_activeRegion purge];
    _activeRegion = nil;

    dispatch_release(_groupForSaving);
    _groupForSaving = NULL;

    dispatch_release(_chunkTaskQueue);
    _chunkTaskQueue = NULL;

    dispatch_release(_queueForSaving);
    _queueForSaving = NULL;
}

- (void)drawActiveChunks
{
    if(_shutdownDrawing) {
        dispatch_semaphore_signal(_semaDrawingIsShutdown);
        return;
    }

    [_terrainShader bind];
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    
    glTranslatef(0.5, 0.5, 0.5);

    [_activeRegion draw];
    
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    
    [_terrainShader unbind];
}

- (void)updateWithCameraModifiedFlags:(unsigned)flags
{
    [_activeRegion updateWithCameraModifiedFlags:flags];
}

- (void)placeBlockAtPoint:(GLKVector3)pos block:(voxel_t)block
{
    [_gridVoxelData replaceItemAtPoint:pos transform:^NSObject<GSGridItem> *(NSObject<GSGridItem> *originalItem) {
        GSChunkVoxelData *modifiedItem = [((GSChunkVoxelData *)originalItem) copyWithEditAtPoint:pos block:block];
        [modifiedItem saveToFile];
        return modifiedItem;
    }];

    // Must notify the active region so that the change will get picked up right away.
    [_activeRegion notifyOfChangeInActiveRegionVBOs];
}

- (BOOL)tryToGetVoxelAtPoint:(GLKVector3)pos voxel:(voxel_t *)voxel
{
    GSChunkVoxelData *chunk = nil;

    assert(voxel);

    if(![self tryToGetChunkVoxelsAtPoint:pos chunk:&chunk]) {
        return NO;
    }

    *voxel = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                               pos.y-chunk.minP.y,
                                                               pos.z-chunk.minP.z)];
    
    return YES;
}

- (voxel_t)voxelAtPoint:(GLKVector3)pos
{
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    
    return [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                             pos.y-chunk.minP.y,
                                                             pos.z-chunk.minP.z)];
}

- (BOOL)enumerateVoxelsOnRay:(GSRay)ray maxDepth:(unsigned)maxDepth withBlock:(void (^)(GLKVector3 p, BOOL *stop, BOOL *fail))block
{
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
    GSIntegerVector3 start = GSIntegerVector3_Make(floorf(ray.origin.x), floorf(ray.origin.y), floorf(ray.origin.z));
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
    GSIntegerVector3 cellBoundary = GSIntegerVector3_Make(x + (stepX > 0 ? 1 : 0),
                                                          y + (stepY > 0 ? 1 : 0),
                                                          z + (stepZ > 0 ? 1 : 0));
    
    // NOTE: For the following calculations, the result will be Single.PositiveInfinity
    // when ray.Direction.X, Y or Z equals zero, which is OK. However, when the left-hand
    // value of the division also equals zero, the result is Single.NaN, which is not OK.
    
    // Determine how far we can travel along the ray before we hit a voxel boundary.
    GLKVector3 tMax = GLKVector3Make((cellBoundary.x - ray.origin.x) / ray.direction.x,    // Boundary is a plane on the YZ axis.
                                    (cellBoundary.y - ray.origin.y) / ray.direction.y,    // Boundary is a plane on the XZ axis.
                                    (cellBoundary.z - ray.origin.z) / ray.direction.z);   // Boundary is a plane on the XY axis.
    if(isnan(tMax.x)) { tMax.x = +INFINITY; }
    if(isnan(tMax.y)) { tMax.y = +INFINITY; }
    if(isnan(tMax.z)) { tMax.z = +INFINITY; }

    // Determine how far we must travel along the ray before we have crossed a gridcell.
    GLKVector3 tDelta = GLKVector3Make(stepX / ray.direction.x,                    // Crossing the width of a cell.
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
        block(GLKVector3Make(x, y, z), &stop, &fail);

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

- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p
{
    GSNeighborhood *neighborhood = [[GSNeighborhood alloc] init];

    const GSIntegerVector3 a=GSIntegerVector3_Make(-1, -1, -1), b=GSIntegerVector3_Make(+1, +1, +1);
    GSIntegerVector3 positionInNeighborhood;
    FOR_BOX(positionInNeighborhood, a, b)
    {
        const GLKVector3 offset = GLKVector3Make(positionInNeighborhood.x,
                                                 positionInNeighborhood.y,
                                                 positionInNeighborhood.z);
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:GLKVector3Add(p, offset)]; // NOTE: may block
        [neighborhood setNeighborAtPosition:positionInNeighborhood neighbor:voxels];
    }
    
    return neighborhood;
}

- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p
{
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    return [_gridGeometryData objectAtPoint:p];
}

- (GSChunkSunlightData *)chunkSunlightAtPoint:(GLKVector3)p
{
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    return [_gridSunlightData objectAtPoint:p];
}

- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p
{
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    return [_gridVoxelData objectAtPoint:p];
}

- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk
{
    assert(p.y >= 0 && p.y < _activeRegionExtent.y);
    assert(chunk);

    GSChunkVoxelData *v = nil;
    BOOL success = [_gridVoxelData objectAtPoint:p
                                        blocking:NO
                                          object:&v
                                 createIfMissing:YES];

    if(success) {
        *chunk = v;
    }

    return success;
}

+ (NSURL *)newTerrainCacheFolderURL
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
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

- (id)newChunkWithMinimumCorner:(GLKVector3)minP
{
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
    [_gridVoxelData evictAllItems];
    [_gridGeometryData evictAllItems];
    [_gridSunlightData evictAllItems];
    [_gridVBOs evictAllItems];
}

@end


static dispatch_source_t createDispatchTimer(uint64_t interval, uint64_t leeway, void (^eventHandler)())
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_global_queue(0, 0));

    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval, leeway);

    dispatch_source_set_event_handler(timer, eventHandler);

    dispatch_resume(timer);

    return timer;
}
