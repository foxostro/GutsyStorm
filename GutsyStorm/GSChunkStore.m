//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "Chunk.h"
#import "GSRay.h"
#import "GSChunkGeometryData.h"
#import "GSChunkVBOs.h"
#import "GSCamera.h"
#import "GSOldGrid.h"
#import "GSNewGrid.h"
#import "GSActiveRegion.h"
#import "GSShader.h"
#import "GSChunkStore.h"
#import "GSBoxedVector.h"


@interface GSChunkStore ()

+ (NSURL *)newWorldSaveFolderURLWithSeed:(NSUInteger)seed;
- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p;
- (BOOL)tryToGetNeighborhoodAtPoint:(GLKVector3)p neighborhood:(GSNeighborhood **)neighborhood;

- (GSChunkVBOs *)chunkVBOsAtPoint:(GLKVector3)p;
- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p;
- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p;

- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk;
- (id)newChunkWithMinimumCorner:(GLKVector3)minP;

@end


@implementation GSChunkStore
{
    GSNewGrid *_gridVBOs;
    GSNewGrid *_gridGeometryData;
    GSOldGrid *_gridVoxelData;

    dispatch_group_t _groupForSaving;
    dispatch_queue_t _chunkTaskQueue;
    dispatch_queue_t _queueForSaving;

    NSLock *_lock;
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

- (id)initWithSeed:(NSUInteger)seed
            camera:(GSCamera *)cam
       terrainShader:(GSShader *)shader
           glContext:(NSOpenGLContext *)context
           generator:(terrain_generator_t)generatorCallback
       postProcessor:(terrain_post_processor_t)postProcessorCallback
{
    self = [super init];
    if (self) {
        _folder = [GSChunkStore newWorldSaveFolderURLWithSeed:seed];
        _groupForSaving = dispatch_group_create();
        _camera = cam;
        _terrainShader = shader;
        _glContext = context;
        _lock = [[NSLock alloc] init];
        _generator = [generatorCallback copy];
        _postProcessor = [postProcessorCallback copy];
        
        /* VBO generation must be performed on the main thread.
         * To preserve responsiveness, limit the number of VBOs we create per frame.
         */
        NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"NumVBOGenerationsAllowedPerFrame"];
        assert(n > 0 && n < INT_MAX);
        _numVBOGenerationsAllowedPerFrame = (int)n;
        
        _chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        dispatch_retain(_chunkTaskQueue);

        _queueForSaving = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        dispatch_retain(_queueForSaving);
        
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
        
        size_t areaXZ = (w/CHUNK_SIZE_X) * (w/CHUNK_SIZE_Z);
        _gridVoxelData = [[GSOldGrid alloc] initWithActiveRegionArea:areaXZ];
        
        _gridGeometryData = [[GSNewGrid alloc] initWithFactory:^NSObject <GSGridItem> * (GLKVector3 minP) {
            GSNeighborhood *neighborhood = [self neighborhoodAtPoint:minP];
            return [[GSChunkGeometryData alloc] initWithMinP:minP neighborhood:neighborhood];
        }];

        _gridVBOs = [[GSNewGrid alloc] initWithFactory:^NSObject <GSGridItem> * (GLKVector3 minP) {
            GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:minP];
            return [[GSChunkVBOs alloc] initWithChunkGeometry:geometry glContext:_glContext];
        }];

        // Each chunk VBO object depends on the single, corresponding chunk geometry object.
        [_gridGeometryData registerDependentGrid:_gridVBOs mapping:^NSSet *(GLKVector3 p) {
            GSBoxedVector *boxedP = [GSBoxedVector boxedVectorWithVector:p];
            return [[NSSet alloc] initWithArray:@[boxedP]];
        }];

        // Do a full refresh fo the active region
        // Active region is bounded at y>=0.
        _activeRegionExtent = GLKVector3Make(w, CHUNK_SIZE_Y, w);
        _activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:_activeRegionExtent];
        [_activeRegion updateWithCameraModifiedFlags:(CAMERA_MOVED|CAMERA_TURNED)
                                              camera:cam
                                       chunkProducer:^GSChunkVBOs *(GLKVector3 p) {
                                           return [self chunkVBOsAtPoint:p];
                                       }];
    }
    
    return self;
}

- (void)waitForSaveToFinish
{
    [_lock lock];
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(_groupForSaving, DISPATCH_TIME_FOREVER); // wait for save operations to complete
    NSLog(@"All chunks have been saved.");
    [_lock unlock];
}

- (void)sync
{
    [self waitForSaveToFinish];
    [_gridGeometryData evictAllItems];
}

- (void)dealloc
{   
    dispatch_release(_groupForSaving);
    dispatch_release(_chunkTaskQueue);
    dispatch_release(_queueForSaving);
}

- (void)drawActiveChunks
{   
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

- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
    [_activeRegion updateWithCameraModifiedFlags:flags
                                          camera:_camera
                                   chunkProducer:^GSChunkVBOs *(GLKVector3 p) {
                                       return [self chunkVBOsAtPoint:p];
                                   }];
}

- (void)placeBlockAtPoint:(GLKVector3)pos block:(voxel_t)newBlock
{
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    [chunk writerAccessToVoxelDataUsingBlock:^{
        voxel_t *block = [chunk pointerToVoxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                                    pos.y-chunk.minP.y,
                                                                                    pos.z-chunk.minP.z)];
        assert(block);
        *block = newBlock;
    }];
    
    /* FIXME: Invalidate sunlight data and geometry for the modified chunk and surrounding chunks.
     * Chunks' sunlight and geometry will be updated on the next update tick.
     */
    //[[self neighborhoodAtPoint:pos] enumerateNeighborsWithBlock:^(GSChunkVoxelData *voxels) {
    //    voxels.dirtySunlight = YES;
    //    [self chunkGeometryAtPoint:voxels.minP].dirty = YES;
    //}];
}

- (BOOL)tryToGetVoxelAtPoint:(GLKVector3)pos voxel:(voxel_t *)voxel
{
    __block voxel_t block;
    GSChunkVoxelData *chunk;

    assert(voxel);

    if(![self tryToGetChunkVoxelsAtPoint:pos chunk:&chunk]) {
        return NO;
    }

    if(![chunk tryReaderAccessToVoxelDataUsingBlock:^{
        block = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                  pos.y-chunk.minP.y,
                                                                  pos.z-chunk.minP.z)];
    }]) {
        return NO;
    }

    *voxel = block;
    return YES;
}

- (voxel_t)voxelAtPoint:(GLKVector3)pos
{
    __block voxel_t block;
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    
    [chunk readerAccessToVoxelDataUsingBlock:^{
        block = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(pos.x-chunk.minP.x,
                                                                  pos.y-chunk.minP.y,
                                                                  pos.z-chunk.minP.z)];
    }];
    
    return block;
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
    
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GLKVector3 a = GLKVector3Add(p, [GSNeighborhood offsetForNeighborIndex:i]);
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:a]; // NOTE: may block
        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }
    
    return neighborhood;
}

- (BOOL)tryToGetNeighborhoodAtPoint:(GLKVector3)p
                       neighborhood:(GSNeighborhood **)outNeighborhood
{
    assert(outNeighborhood);

    GSNeighborhood *neighborhood = [[GSNeighborhood alloc] init];

    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GLKVector3 a = GLKVector3Add(p, [GSNeighborhood offsetForNeighborIndex:i]);
        GSChunkVoxelData *voxels = nil;

        if(![self tryToGetChunkVoxelsAtPoint:a chunk:&voxels]) {
            return NO;
        }

        [neighborhood setNeighborAtIndex:i neighbor:voxels];
    }

    *outNeighborhood = neighborhood;
    return YES;
}

- (GSChunkVBOs *)chunkVBOsAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < _activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    return [_gridVBOs objectAtPoint:p];
}

- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < _activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    return [_gridGeometryData objectAtPoint:p];
}

- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < _activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkVoxelData *v = [_gridVoxelData objectAtPoint:p
                                          objectFactory:^NSObject <GSGridItem> * (GLKVector3 minP) {
                                              return [self newChunkWithMinimumCorner:minP];
                                          }];
    
    return v;
}

- (BOOL)tryToGetChunkVoxelsAtPoint:(GLKVector3)p chunk:(GSChunkVoxelData **)chunk
{
    BOOL success;
    GSChunkVoxelData *v;

    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < _activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    assert(chunk);

    success = [_gridVoxelData tryToGetObjectAtPoint:p
                                            object:&v
                                     objectFactory:^id(GLKVector3 minP) {
                                         return [self newChunkWithMinimumCorner:minP];
                                     }];

    if(success) {
        *chunk = v;
        return YES;
    } else {
        return NO;
    }
}

+ (NSURL *)newWorldSaveFolderURLWithSeed:(NSUInteger)seed
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    
    folder = [folder stringByAppendingPathComponent:@"GutsyStorm"];
    folder = [folder stringByAppendingPathComponent:@"save"];
    folder = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu",seed]];
    NSLog(@"ChunkStore will save chunks to folder: %@", folder);
    
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        NSLog(@"Failed to create save folder: %@", folder);
    }
    
    NSURL *url = [[NSURL alloc] initFileURLWithPath:folder isDirectory:YES];
    
    if(![url checkResourceIsReachableAndReturnError:NULL]) {
        NSLog(@"ChunkStore's Save folder not reachable: %@", folder);
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

@end