//
//  GSChunkStore.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/24/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <OpenGL/glu.h>
#import <assert.h>
#import <cache.h>
#import <GLKit/GLKMath.h>
#import "GSRay.h"
#import "GSBoxedRay.h"
#import "GSBoxedVector.h"
#import "GSChunkStore.h"
#import "GSNoise.h"

static float groundGradient(float terrainHeight, GLKVector3 p);
static void generateTerrainVoxel(unsigned seed, float terrainHeight, GLKVector3 p, voxel_t *outVoxel);


@interface GSChunkStore (Private)

+ (NSURL *)newWorldSaveFolderURLWithSeed:(unsigned)seed;
- (void)updateChunkVisibilityForActiveRegion;
- (void)updateActiveChunksWithCameraModifiedFlags:(unsigned)flags;
- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p;
- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p;
- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p;

@end


@implementation GSChunkStore

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if(![defaults objectForKey:@"ActiveRegionExtent"]) {
        NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:@"256", @"ActiveRegionExtent", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    if(![defaults objectForKey:@"NumVBOGenerationsAllowedPerFrame"]) {
        NSDictionary *values = [NSDictionary dictionaryWithObjectsAndKeys:@"64", @"NumVBOGenerationsAllowedPerFrame", nil];
        [[NSUserDefaults standardUserDefaults] registerDefaults:values];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (id)initWithSeed:(unsigned)_seed
            camera:(GSCamera *)_camera
     terrainShader:(GSShader *)_terrainShader
         glContext:(NSOpenGLContext *)_glContext
{
    self = [super init];
    if (self) {
        // Initialization code here.
        seed = _seed;
        terrainHeight = 40.0;
        folder = [GSChunkStore newWorldSaveFolderURLWithSeed:seed];
        groupForSaving = dispatch_group_create();
        
        camera = _camera;
        [camera retain];
        oldCenterChunkID = [GSChunkData chunkIDWithChunkMinCorner:[GSChunkData minCornerForChunkAtPoint:[camera cameraEye]]];
        [oldCenterChunkID retain];
        
        terrainShader = _terrainShader;
        [terrainShader retain];
        
        glContext = _glContext;
        [glContext retain];
        
        lock = [[NSLock alloc] init];
        
        timeUntilNextPeriodicChunkUpdate = 0.0;
        timeBetweenPerioducChunkUpdates = 1.0;
        activeRegionNeedsUpdate = 0;
        
        /* VBO generation must be performed on the main thread.
         * To preserve responsiveness, limit the number of VBOs we create per frame.
         */
        NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"NumVBOGenerationsAllowedPerFrame"];
        assert(n > 0 && n < INT_MAX);
        numVBOGenerationsAllowedPerFrame = (int)n;
        
        chunkTaskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:@"ActiveRegionExtent"];
        
        size_t areaXZ = (w/CHUNK_SIZE_X) * (w/CHUNK_SIZE_Z);
        gridGeometryData = [[GSGrid alloc] initWithActiveRegionArea:areaXZ];
        gridVoxelData = [[GSGrid alloc] initWithActiveRegionArea:areaXZ];
        
        // Do a full refresh fo the active region
        // Active region is bounded at y>=0.
        activeRegionExtent = GLKVector3Make(w, CHUNK_SIZE_Y, w);
        activeRegion = [[GSActiveRegion alloc] initWithActiveRegionExtent:activeRegionExtent];
        [activeRegion updateWithSorting:YES camera:camera chunkProducer:^GSChunkGeometryData *(GLKVector3 p) {
            return [self chunkGeometryAtPoint:p];
        }];
        needsChunkVisibilityUpdate = 1;
        
    }
    
    return self;
}


- (void)waitForSaveToFinish
{
    [lock lock];
    NSLog(@"Waiting for all chunk-saving tasks to complete.");
    dispatch_group_wait(groupForSaving, DISPATCH_TIME_FOREVER); // wait for save operations to complete
    NSLog(@"All chunks have been saved.");
    [lock unlock];
}


- (void)dealloc
{
    [self waitForSaveToFinish];
    dispatch_release(groupForSaving);
    
    [gridVoxelData release];
    [gridGeometryData release];
    [camera release];
    [folder release];
    [terrainShader release];
    [glContext release];
    [lock release];
    [activeRegion release];
    dispatch_release(chunkTaskQueue);
    
    [super dealloc];
}


- (void)drawActiveChunks
{
    [terrainShader bind];
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    
    glTranslatef(0.5, 0.5, 0.5);
    
    // Update chunk visibility flags now. We've been told it's necessary.
    if(OSAtomicCompareAndSwapIntBarrier(1, 0, &needsChunkVisibilityUpdate)) {
        [self updateChunkVisibilityForActiveRegion];
    }

    __block NSUInteger numVBOGenerationsRemaining = numVBOGenerationsAllowedPerFrame;
    [activeRegion enumerateActiveChunkWithBlock:^(GSChunkGeometryData *chunk) {
        assert(chunk);
        if(chunk->visible && [chunk drawGeneratingVBOsIfNecessary:(numVBOGenerationsRemaining>0)]) {
            numVBOGenerationsRemaining--;
        };
    }];
    
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    
    [terrainShader unbind];
}


// Try to update asynchronously dirty chunk sunlight. Skip any that would block due to lock contention.
- (void)tryToUpdateDirtySunlight
{
    void (^b)(GLKVector3) = ^(GLKVector3 p) {
        GSChunkVoxelData *voxels = [self chunkVoxelsAtPoint:p];
        dispatch_async(chunkTaskQueue, ^{
            if(voxels.dirtySunlight) {
                GSNeighborhood *neighborhood = [self neighborhoodAtPoint:voxels.centerP];
                [voxels tryToRebuildSunlightWithNeighborhood:neighborhood completionHandler:^{
                    GSChunkGeometryData *geometry = [self chunkGeometryAtPoint:p];
                    geometry.dirty = YES;
                    [geometry tryToUpdateWithVoxelData:neighborhood]; // make an effort to update geometry immediately
                }];
            }
        });
    };
    
    [activeRegion enumeratePointsInActiveRegionNearCamera:camera usingBlock:b];
}


// Try to asynchronously update dirty chunk geometry. Skip any that would block due to lock contention.
- (void)tryToUpdateDirtyGeometry
{
    void (^b)(GSChunkGeometryData *) = ^(GSChunkGeometryData *geometry) {
        dispatch_async(chunkTaskQueue, ^{
            if(geometry.dirty) {
                [geometry tryToUpdateWithVoxelData:[self neighborhoodAtPoint:geometry.centerP]];
            }
        });
    };
    
    [activeRegion enumerateActiveChunkWithBlock:b];
}


- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)flags
{
    timeUntilNextPeriodicChunkUpdate -= dt;
    if(timeUntilNextPeriodicChunkUpdate < 0) {
        timeBetweenPerioducChunkUpdates = timeBetweenPerioducChunkUpdates;
        
        dispatch_async(chunkTaskQueue, ^{
            [self tryToUpdateDirtySunlight];
            [self tryToUpdateDirtyGeometry];
        
            if(OSAtomicCompareAndSwap32Barrier(1, 0, &activeRegionNeedsUpdate)) {
                [self updateActiveChunksWithCameraModifiedFlags:(CAMERA_MOVED|CAMERA_TURNED)];
            }
        });
    }
    
    if((flags & CAMERA_MOVED) || (flags & CAMERA_TURNED)) {
        OSAtomicCompareAndSwap32Barrier(0, 1, &activeRegionNeedsUpdate);
    }
}


- (void)placeBlockAtPoint:(GLKVector3)pos block:(voxel_t)newBlock
{
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    [chunk writerAccessToVoxelDataUsingBlock:^{
        GLKVector3 chunkLocalP;
        voxel_t *block;
        
        chunkLocalP = GLKVector3Subtract(pos, chunk.minP);
        
        block = [chunk pointerToVoxelAtLocalPosition:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];
        assert(block);
        
        *block = newBlock;
    }];
    
    /* Invalidate sunlight data and geometry for the modified chunk and surrounding chunks.
     * Chunks' sunlight and geometry will be updated on the next update tick.
     */
    [[self neighborhoodAtPoint:pos] enumerateNeighborsWithBlock:^(GSChunkVoxelData *voxels) {
        voxels.dirtySunlight = YES;
        [self chunkGeometryAtPoint:voxels.centerP].dirty = YES;
    }];
}


- (voxel_t)voxelAtPoint:(GLKVector3)pos
{
    __block voxel_t block;
    GSChunkVoxelData *chunk = [self chunkVoxelsAtPoint:pos];
    
    [chunk readerAccessToVoxelDataUsingBlock:^{
        GLKVector3 chunkLocalP = GLKVector3Subtract(pos, chunk.minP);
        block = [chunk voxelAtLocalPosition:GSIntegerVector3_Make(chunkLocalP.x, chunkLocalP.y, chunkLocalP.z)];
    }];
    
    return block;
}


- (void)enumerateVoxelsOnRay:(GSRay)ray maxDepth:(unsigned)maxDepth withBlock:(void (^)(GLKVector3 p, BOOL *stop))block
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
        if(y >= activeRegionExtent.y || y < 0) {
            return; // The vertical extent of the world is limited.
        }
        
        BOOL stop = NO;
        block(GLKVector3Make(x, y, z), &stop);
        if(stop) {
            return;
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
}

@end


@implementation GSChunkStore (Private)

- (GSNeighborhood *)neighborhoodAtPoint:(GLKVector3)p
{
    GSNeighborhood *neighborhood = [[[GSNeighborhood alloc] init] autorelease];
    
    for(neighbor_index_t i = 0; i < CHUNK_NUM_NEIGHBORS; ++i)
    {
        GLKVector3 a = GLKVector3Add(p, [GSNeighborhood offsetForNeighborIndex:i]);
        [neighborhood setNeighborAtIndex:i neighbor:[self chunkVoxelsAtPoint:a]];
    }
    
    return neighborhood;
}


- (GSChunkGeometryData *)chunkGeometryAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkGeometryData *g = [gridGeometryData objectAtPoint:p objectFactory:^id(GLKVector3 minP) {
        // Chunk geometry will be generated later and is only marked "dirty" for now.
        return [[[GSChunkGeometryData alloc] initWithMinP:minP
                                                   folder:folder
                                           groupForSaving:groupForSaving
                                           chunkTaskQueue:chunkTaskQueue
                                                glContext:glContext] autorelease];
    }];
    
    return g;
}


- (GSChunkVoxelData *)chunkVoxelsAtPoint:(GLKVector3)p
{
    assert(p.y >= 0); // world does not extend below y=0
    assert(p.y < activeRegionExtent.y); // world does not extend above y=activeRegionExtent.y
    
    GSChunkVoxelData *v = [gridVoxelData objectAtPoint:p objectFactory:^id(GLKVector3 minP) {
        return [[[GSChunkVoxelData alloc] initWithMinP:minP
                                                folder:folder
                                        groupForSaving:groupForSaving
                                        chunkTaskQueue:chunkTaskQueue
                                             generator:^(GLKVector3 a, voxel_t *voxel) {
                                                 generateTerrainVoxel(seed, terrainHeight, a, voxel);
                                             }] autorelease];
    }];
    
    return v;
}


+ (NSURL *)newWorldSaveFolderURLWithSeed:(unsigned)seed
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *folder = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    folder = [folder stringByAppendingPathComponent:@"GutsyStorm"];
    folder = [folder stringByAppendingPathComponent:@"save"];
    folder = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",seed]];
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


- (void)updateChunkVisibilityForActiveRegion
{
    //CFAbsoluteTime timeStart = CFAbsoluteTimeGetCurrent();

    GSFrustum *frustum = [camera frustum];
    
    [activeRegion enumerateActiveChunkWithBlock:^(GSChunkGeometryData *geometry) {
        if(geometry) {
            geometry->visible = (GS_FRUSTUM_OUTSIDE != [frustum boxInFrustumWithBoxVertices:geometry->corners]);
        }
    }];
    
    //CFAbsoluteTime timeEnd = CFAbsoluteTimeGetCurrent();
    //NSLog(@"Finished chunk visibility checks. It took %.3fs", timeEnd - timeStart);
}


- (void)updateActiveChunksWithCameraModifiedFlags:(unsigned)flags
{
    // If the camera moved then recalculate the set of active chunks.
    if(flags & CAMERA_MOVED) {
        // We can avoid a lot of work if the camera hasn't moved enough to add/remove any chunks in the active region.
        chunk_id_t newCenterChunkID = [GSChunkData chunkIDWithChunkMinCorner:[GSChunkData minCornerForChunkAtPoint:[camera cameraEye]]];
        
        if(![oldCenterChunkID isEqual:newCenterChunkID]) {
            [activeRegion updateWithSorting:NO camera:camera chunkProducer:^GSChunkGeometryData *(GLKVector3 p) {
                return [self chunkGeometryAtPoint:p];
            }];

            // Now save this chunk ID for comparison next update.
            [oldCenterChunkID release];
            oldCenterChunkID = newCenterChunkID;
            [oldCenterChunkID retain];
        }
    }
    
    // If the camera moved or turned then recalculate chunk visibility.
    if((flags & CAMERA_TURNED) || (flags & CAMERA_MOVED)) {
        OSAtomicCompareAndSwapIntBarrier(0, 1, &needsChunkVisibilityUpdate);
    }
}

@end


// Return a value between -1 and +1 so that a line through the y-axis maps to a smooth gradient of values from -1 to +1.
static float groundGradient(float terrainHeight, GLKVector3 p)
{
    const float y = p.y;
    
    if(y < 0.0) {
        return -1;
    } else if(y > terrainHeight) {
        return +1;
    } else {
        return 2.0*(y/terrainHeight) - 1.0;
    }
}


// Generates a voxel for the specified point in space. Returns that voxel in `outVoxel'.
static void generateTerrainVoxel(unsigned seed, float terrainHeight, GLKVector3 p, voxel_t *outVoxel)
{
    static dispatch_once_t onceToken;
    static GSNoise *noiseSource0;
    static GSNoise *noiseSource1;
    
    BOOL groundLayer = NO;
    BOOL floatingMountain = NO;
    
    assert(outVoxel);
    
    dispatch_once(&onceToken, ^{
        noiseSource0 = [[GSNoise alloc] initWithSeed:seed];
        noiseSource1 = [[GSNoise alloc] initWithSeed:seed+1];
    });
    
    // Normal rolling hills
    {
        const float freqScale = 0.025;
        float n = [noiseSource0 noiseAtPointWithFourOctaves:GLKVector3MultiplyScalar(p, freqScale)];
        float turbScaleX = 2.0;
        float turbScaleY = terrainHeight / 2.0;
        float yFreq = turbScaleX * ((n+1) / 2.0);
        float t = turbScaleY * [noiseSource1 noiseAtPoint:GLKVector3Make(p.x*freqScale, p.y*yFreq*freqScale, p.z*freqScale)];
        groundLayer = groundGradient(terrainHeight, GLKVector3Make(p.x, p.y + t, p.z)) <= 0;
    }
    
    // Giant floating mountain
    {
        /* The floating mountain is generated by starting with a sphere and applying turbulence to the surface.
         * The upper hemisphere is also squashed to make the top flatter.
         */
        
        GLKVector3 mountainCenter = GLKVector3Make(50, 50, 80);
        GLKVector3 toMountainCenter = GLKVector3Subtract(mountainCenter, p);
        float distance = GLKVector3Length(toMountainCenter);
        float radius = 30.0;
        
        // Apply turbulence to the surface of the mountain.
        float freqScale = 0.70;
        float turbScale = 15.0;
        
        // Avoid generating noise when too far away from the center to matter.
        if(distance > 2.0*radius) {
            floatingMountain = NO;
        } else {
            // Convert the point into spherical coordinates relative to the center of the mountain.
            float azimuthalAngle = acosf(toMountainCenter.z / distance);
            float polarAngle = atan2f(toMountainCenter.y, toMountainCenter.x);
            
            float t = turbScale * [noiseSource0 noiseAtPointWithFourOctaves:GLKVector3Make(azimuthalAngle * freqScale,
                                                                                              polarAngle * freqScale, 0.0)];
            
            // Flatten the top.
            if(p.y > mountainCenter.y) {
                radius -= (p.y - mountainCenter.y) * 3;
            }
            
            floatingMountain = (distance+t) < radius;
        }
    }
    
    *outVoxel = (groundLayer || floatingMountain) ? ~VOXEL_EMPTY : VOXEL_EMPTY;
}