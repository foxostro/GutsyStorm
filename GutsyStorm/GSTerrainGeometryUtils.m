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
#import "GSTerrainBuffer.h"
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
    
    GSTerrainBuffer *lightBuffer = sunlight.sunlight;

    for(GSBoxedTerrainVertex *vertex in vertices)
    {
        GSTerrainVertex v = vertex.v;
        
        vector_float3 vertexPos = (vector_float3){v.position[0], v.position[1], v.position[2]};
        vector_long3 normal = (vector_long3){v.normal[0], v.normal[1], v.normal[2]};
        
        uint8_t sunlightValue = [lightBuffer lightForVertexAtPoint:vertexPos
                                                        withNormal:normal
                                                              minP:chunkMinP];
        
        vector_float4 color = {0};
        
        color.y = 204.0f * (sunlightValue / (float)CHUNK_LIGHTING_MAX) + 51.0f; // sunlight in the green channel
        
        v.color[0] = color.x;
        v.color[1] = color.y;
        v.color[2] = color.z;
        v.color[3] = color.w;
        
        vertex.v = v;
    }
    
    return vertices;
}