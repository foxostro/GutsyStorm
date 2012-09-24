//
//  Voxel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Voxel_h
#define GutsyStorm_Voxel_h


#ifdef DEBUG // TODO: find a better home for this macro
#    define DebugLog(...) do { NSLog(__VA_ARGS__); } while(0);
#else
#    define DebugLog(...)
#endif


#define CHUNK_SIZE_X (8)
#define CHUNK_SIZE_Y (128)
#define CHUNK_SIZE_Z (8)

#define CHUNK_LIGHTING_MAX (7)

#define VOXEL_EMPTY   (1) // a flag on the first LSB
#define VOXEL_OUTSIDE (2) // a flag on the second LSB

// Used for indexing into chunk-sized buffers
#define INDEX(x,y,z) ((size_t)(((x)*CHUNK_SIZE_Y*CHUNK_SIZE_Z) + ((y)*CHUNK_SIZE_Z) + (z)))

// Used for indexing into neighborhood-sized buffers.
#define INDEX2(x,y,z) ((((ssize_t)(x)+CHUNK_SIZE_X)*CHUNK_SIZE_Y*(3*CHUNK_SIZE_Z)) + ((ssize_t)(y)*(3*CHUNK_SIZE_Z)) + ((ssize_t)(z)+CHUNK_SIZE_Z))

typedef uint8_t voxel_t;


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
    const voxel_t originalVoxel = *voxel;
    const voxel_t emptyVoxel = originalVoxel | VOXEL_EMPTY;
    const voxel_t nonEmptyVoxel = originalVoxel & ~VOXEL_EMPTY;
    *voxel = empty ? emptyVoxel : nonEmptyVoxel;
}


static inline void markVoxelAsOutside(BOOL outside, voxel_t * voxel)
{
    const voxel_t originalVoxel = *voxel;
    const voxel_t outsideVoxel = originalVoxel | VOXEL_OUTSIDE;
    const voxel_t nonOutsideVoxel = originalVoxel & ~VOXEL_OUTSIDE;
    *voxel = outside ? outsideVoxel : nonOutsideVoxel;
}


static inline BOOL isVoxelEmpty(voxel_t voxel)
{
    return voxel & VOXEL_EMPTY;
}


static inline BOOL isVoxelOutside(voxel_t voxel)
{
    return voxel & VOXEL_OUTSIDE;
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
