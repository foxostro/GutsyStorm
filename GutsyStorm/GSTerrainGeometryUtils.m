//
//  GSTerrainGeometryUtils.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/21/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGeometryUtils.h"
#import "GSChunkVoxelData.h"
#import "GSChunkSunlightData.h"
#import "GSVoxelNeighborhood.h"
#import "GSBoxedTerrainVertex.h"
#import "GSBox.h"
#import "GSBlockMesh.h"
#import "GSBlockMeshCube.h"
#import "GSBlockMeshRamp.h"
#import "GSBlockMeshInsideCorner.h"
#import "GSBlockMeshOutsideCorner.h"

NSArray<GSBoxedTerrainVertex *> * _Nonnull
GSTerrainGenerateGeometry(GSChunkSunlightData * _Nonnull sunlight, vector_float3 chunkMinP, NSUInteger i)
{
    assert(sunlight);
    
    GSIntAABB box = GSGeometrySubchunkBoxInt(chunkMinP, i);
    
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
    FOR_BOX(pos, box)
    {
        vector_long3 chunkLocalPos = vector_long(pos - chunkMinP);
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