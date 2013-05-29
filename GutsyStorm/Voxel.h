//
//  Voxel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Voxel_h
#define GutsyStorm_Voxel_h

#import <GLKit/GLKQuaternion.h>
#import "GSIntegerVector3.h"


#if 0 && defined(DEBUG) // TODO: find a better home for this macro
#    define DebugLog(...) do { NSLog(__VA_ARGS__); } while(0);
#else
#    define DebugLog(...)
#endif


#define CHUNK_LIGHTING_MAX (7)
#define WORLD_CEILING_HEIGHT (128)

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
    VOXEL_TYPE_CORNER_OUTSIDE,
    NUM_VOXEL_TYPES
} voxel_type_t;


/* The direction of the voxel. Affects the orientation of the mesh and traversibility. */
typedef enum
{
    VOXEL_DIR_NORTH=0, // ( 0, 0, +1)
    VOXEL_DIR_EAST,    // (+1, 0,  0)
    VOXEL_DIR_SOUTH,   // ( 0, 0, -1)
    VOXEL_DIR_WEST,    // (-1, 0,  0)
    NUM_VOXEL_DIRECTIONS
} voxel_dir_t;

_Static_assert(0 == (int)VOXEL_DIR_NORTH, "The ordering of voxel_dir_t matters.");
_Static_assert(1 == (int)VOXEL_DIR_EAST,  "The ordering of voxel_dir_t matters.");
_Static_assert(2 == (int)VOXEL_DIR_SOUTH, "The ordering of voxel_dir_t matters.");
_Static_assert(3 == (int)VOXEL_DIR_WEST,  "The ordering of voxel_dir_t matters.");


static inline GLKQuaternion quaternionForDirection(voxel_dir_t dir)
{
    return GLKQuaternionMakeWithAngleAndAxis((int)dir * M_PI_2, 0, 1, 0);
}


static inline GSIntegerVector3 integerVectorForDirection(voxel_dir_t dir)
{
    GLKVector3 vector = GLKQuaternionRotateVector3(quaternionForDirection(dir), GLKVector3Make(0, 0, 1));
    GSIntegerVector3 iVector = GSIntegerVector3_Make(vector.x, vector.y, vector.z);
    return iVector;
}


/* The texture to use for the voxel mesh. */
typedef enum
{
    VOXEL_TEX_GRASS=0,
    VOXEL_TEX_DIRT,
    VOXEL_TEX_SIDE,
    VOXEL_TEX_STONE,
    NUM_VOXEL_TEXTURES
} voxel_tex_t;


typedef struct
{
    /* Indicates the voxel transmits light as if it were air. (used by the lighting engine) */
    uint8_t opaque:1;

    /* Indicates the voxel piece is upside down. */
    uint8_t upsideDown:1;

    /* The direction of the voxel. (rotation around the Y-axis) Affects the orientation of the mesh and traversibility. */
    uint8_t dir:2;

    /* The voxel type affects the mesh which is used when drawing it. */
    uint8_t type:3;

    /* Voxel texture. This is used as an index into the terrain texture array. */
    uint8_t tex:2;
    
    /* Indicates the voxel has an occluded path to the sky along the Y axis. (used by the lighting engine) */
    uint8_t outside:1;
} voxel_t;

_Static_assert(NUM_VOXEL_DIRECTIONS <= (1<<2), "NUM_VOXEL_DIRECTIONS must be able to work with a 2-bit `dir' field.");
_Static_assert(NUM_VOXEL_TYPES <= (1<<3),      "NUM_VOXEL_TYPES must be able to work with a 3-bit `type' field.");
_Static_assert(NUM_VOXEL_TEXTURES <= (1<<2),   "NUM_VOXEL_TEXTURES must be able to work with a 2-bit `tex' field.");


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


extern const GSIntegerVector3 chunkSize;
extern const GSIntegerVector3 offsetForFace[FACE_NUM_FACES];
extern const GSIntegerVector3 combinedMinP;
extern const GSIntegerVector3 combinedMaxP;


#define CHUNK_SIZE_X (16)
#define CHUNK_SIZE_Y (64)
#define CHUNK_SIZE_Z (16)

_Static_assert(CHUNK_SIZE_X > 0 && CHUNK_SIZE_X < 256, "CHUNK_SIZE_X must be representable by an 8-bit unsigned integer");
_Static_assert(CHUNK_SIZE_Y > 0 && CHUNK_SIZE_Y < 256, "CHUNK_SIZE_Y must be representable by an 8-bit unsigned integer");
_Static_assert(CHUNK_SIZE_Z > 0 && CHUNK_SIZE_Z < 256, "CHUNK_SIZE_Z must be representable by an 8-bit unsigned integer");


static inline GLKVector3 MinCornerForChunkAtPoint(GLKVector3 p)
{
    return GLKVector3Make(floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}

static inline GLKVector3 MinCornerForChunkAtPoint2(float x, float y, float z)
{
    return GLKVector3Make(floorf(x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                          floorf(y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                          floorf(z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z);
}

#endif
