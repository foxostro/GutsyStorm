//
//  Voxel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Voxel_h
#define GutsyStorm_Voxel_h

#import "GSIntegerVector3.h"


#ifdef DEBUG // TODO: find a better home for this macro
#    define DebugLog(...) do { NSLog(__VA_ARGS__); } while(0);
#else
#    define DebugLog(...)
#endif


#define CHUNK_SIZE_X (16)
#define CHUNK_SIZE_Y (128)
#define CHUNK_SIZE_Z (16)

#define CHUNK_LIGHTING_MAX (MIN(CHUNK_SIZE_X, CHUNK_SIZE_Z) - 1)

#define FOR_BOX(p, minP, maxP) for((p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                   for((p).y = (minP).y; (p).y < (maxP).y; ++(p).y) \
                                       for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)

#define FOR_Y_COLUMN_IN_BOX(p, minP, maxP) for((p).y = (minP).y, (p).x = (minP).x; (p).x < (maxP).x; ++(p).x) \
                                             for((p).z = (minP).z; (p).z < (maxP).z; ++(p).z)


static inline size_t INDEX_BOX(GSIntegerVector3 p, GSIntegerVector3 minP, GSIntegerVector3 maxP)
{
    const size_t sizeY = maxP.y - minP.y;
    const size_t sizeZ = maxP.z - minP.z;
    
    // Columns in the y-axis are contiguous in memory.
    return ((p.x-minP.x)*sizeY*sizeZ) + ((p.z-minP.z)*sizeY) + (p.y-minP.y);
}


/* The voxel type affects the mesh which is used when drawing it.
 * According to voxel_t, there can only be 8 types.
 */
typedef enum
{
    VOXEL_TYPE_EMPTY=0,
    VOXEL_TYPE_CUBE,
    VOXEL_TYPE_RAMP,
    VOXEL_TYPE_CORNER_INSIDE,
    VOXEL_TYPE_CORNER_OUTSIDE
} voxel_type_t;


/* The direction of the voxel. Affects the orientation of the mesh and traversibility. */
typedef enum
{
    VOXEL_DIR_NORTH=0,
    VOXEL_DIR_EAST,
    VOXEL_DIR_SOUTH,
    VOXEL_DIR_WEST
} voxel_dir_t;


typedef struct
{
    /* Cache the results of the calculation of whether this vertex is outside or inside. */
    BOOL outside;

    /* The direction of the voxel. Affects the orientation of the mesh and traversibility. */
    uint8_t dir;

    /* The voxel type affects the mesh which is used when drawing it. */
    uint8_t type;

    /* Voxel texture. This is used as an index into the terrain texture array. */
    uint8_t tex;
} voxel_t;


typedef enum
{
    FACE_TOP=0,
    FACE_BOTTOM,
    FACE_BACK,
    FACE_FRONT,
    FACE_RIGHT,
    FACE_LEFT,
    FACE_NUM_FACES
} face_t;


static inline void markVoxelAsEmpty(BOOL empty, voxel_t * voxel)
{
    voxel->type = empty ? VOXEL_TYPE_EMPTY : VOXEL_TYPE_CUBE;
}


static inline void markVoxelAsOutside(BOOL outside, voxel_t * voxel)
{
    voxel->outside = outside;
}


static inline BOOL isVoxelEmpty(voxel_t voxel)
{
    return voxel.type == VOXEL_TYPE_EMPTY;
}


static inline BOOL isVoxelOutside(voxel_t voxel)
{
    return voxel.outside;
}


static inline unsigned averageLightValue(unsigned a, unsigned b, unsigned c, unsigned d)
{
    return (a+b+c+d) >> 2;
}


typedef uint16_t block_lighting_vertex_t;


// Pack four block lighting values into a single unsigned integer value.
static inline block_lighting_vertex_t packBlockLightingValuesForVertex(unsigned v0, unsigned v1, unsigned v2, unsigned v3)
{
    block_lighting_vertex_t packed1;
    
    const unsigned m = 15;
    
    packed1 =  (v0 & m)
            | ((v1 <<  4) & (m <<  4))
            | ((v2 <<  8) & (m <<  8))
            | ((v3 << 12) & (m << 12));
    
    return packed1;
}


// Extact four block lighting values from a single unsigned integer value.
static inline void unpackBlockLightingValuesForVertex(block_lighting_vertex_t packed, unsigned * outValues)
{
    assert(outValues);
    
    const unsigned m = 15;
    
    outValues[0] = (packed & m);
    outValues[1] = (packed & (m <<  4)) >>  4;
    outValues[2] = (packed & (m <<  8)) >>  8;
    outValues[3] = (packed & (m << 12)) >> 12;
}


typedef struct
{
    /* Each face has four vertices, and we need a brightness factor for
     * all 24 of these vertices.
     */
    
    block_lighting_vertex_t face[FACE_NUM_FACES];
} block_lighting_t;


#endif
