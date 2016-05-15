//
//  GSTerrainRayMarcher.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <simd/vector.h>
#import "GSTerrainRayMarcher.h"
#import "GSIntegerVector3.h"
#import "GSVectorUtils.h"
#import "GSVoxel.h"


@implementation GSTerrainRayMarcher
{
    __weak GSTerrainChunkStore *_chunkStore;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
{
    NSParameterAssert(chunkStore);
    if (self = [super init]) {
        _chunkStore = chunkStore;
    }
    return self;
}

- (BOOL)enumerateVoxelsOnRay:(GSRay)ray
                    maxDepth:(unsigned)maxDepth
                   withBlock:(void (^ _Nonnull)(vector_float3 p, BOOL * _Nonnull stop, BOOL * _Nonnull fail))block
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
    vector_long3 start = vector_long(floor(ray.origin));
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
    vector_long3 cellBoundary = (vector_long3){x + (stepX > 0 ? 1 : 0),
                                               y + (stepY > 0 ? 1 : 0),
                                               z + (stepZ > 0 ? 1 : 0)};
    
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
        if(y >= GSChunkSizeIntVec3.y || y < 0) {
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

@end
