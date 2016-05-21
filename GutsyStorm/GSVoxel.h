//
//  GSVoxel.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/11/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSQuaternion.h"

#define CHUNK_LIGHTING_MAX (12)

#define CHUNK_SIZE_X (16)
#define CHUNK_SIZE_Y (256)
#define CHUNK_SIZE_Z (16)

_Static_assert((CHUNK_LIGHTING_MAX <= (CHUNK_SIZE_X - 1)) && (CHUNK_LIGHTING_MAX <= (CHUNK_SIZE_Z - 1)),
               "Lots of logic here assumes that lighting changes will never affect more than one chunk and it's neighbors.");

/* The voxel type affects the mesh which is used when drawing it.
 * According to GSVoxel, there can only be 8 types.
 */
typedef enum
{
    VOXEL_TYPE_EMPTY=0,
    VOXEL_TYPE_GROUND,
    NUM_VOXEL_TYPES
} GSVoxelType;


/* The direction of the voxel. Affects the orientation of the mesh and traversibility. */
typedef enum
{
    VOXEL_DIR_NORTH=0, // ( 0, 0, +1)
    VOXEL_DIR_EAST,    // (+1, 0,  0)
    VOXEL_DIR_SOUTH,   // ( 0, 0, -1)
    VOXEL_DIR_WEST,    // (-1, 0,  0)
    NUM_VOXEL_DIRECTIONS
} GSVoxelDirection;

_Static_assert(0 == (int)VOXEL_DIR_NORTH, "The ordering of GSVoxelDirection matters.");
_Static_assert(1 == (int)VOXEL_DIR_EAST,  "The ordering of GSVoxelDirection matters.");
_Static_assert(2 == (int)VOXEL_DIR_SOUTH, "The ordering of GSVoxelDirection matters.");
_Static_assert(3 == (int)VOXEL_DIR_WEST,  "The ordering of GSVoxelDirection matters.");


static inline vector_float4 GSQuaternionForVoxelDirection(GSVoxelDirection dir)
{
    return quaternion_make_with_angle_and_axis((int)dir * M_PI_2, 0, 1, 0);
}


/* The texture to use for the voxel mesh. */
typedef enum
{
    VOXEL_TEX_GRASS=0,
    VOXEL_TEX_DIRT,
    VOXEL_TEX_SIDE,
    VOXEL_TEX_STONE,
    NUM_VOXEL_TEXTURES
} GSVoxelTexture;


typedef struct
{
    /* Cache the results of the calculation of whether this vertex is outside or inside. */
    uint8_t outside:1;
    
    /* Indicates a torch is placed on this block. It is a light source. */
    uint8_t torch:1;

    /* Indicates the block above the one for this vertex is an empty, air block. */
    uint8_t exposedToAirOnTop:1;

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
} GSVoxel;

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
} GSVoxelFace;


extern const vector_long3 GSChunkSizeIntVec3;
extern const vector_long3 GSOffsetForVoxelFace[FACE_NUM_FACES];
extern const vector_long3 GSCombinedMinP;
extern const vector_long3 GSCombinedMaxP;


static inline vector_float3 GSMinCornerForChunkAtPoint(vector_float3 p)
{
    return (vector_float3){floorf(p.x / CHUNK_SIZE_X) * CHUNK_SIZE_X,
                           floorf(p.y / CHUNK_SIZE_Y) * CHUNK_SIZE_Y,
                           floorf(p.z / CHUNK_SIZE_Z) * CHUNK_SIZE_Z};
}

typedef enum
{
    CHUNK_NEIGHBOR_POS_X_NEG_Z = 0,
    CHUNK_NEIGHBOR_POS_X_ZER_Z = 1,
    CHUNK_NEIGHBOR_POS_X_POS_Z = 2,
    CHUNK_NEIGHBOR_NEG_X_NEG_Z = 3,
    CHUNK_NEIGHBOR_NEG_X_ZER_Z = 4,
    CHUNK_NEIGHBOR_NEG_X_POS_Z = 5,
    CHUNK_NEIGHBOR_ZER_X_NEG_Z = 6,
    CHUNK_NEIGHBOR_ZER_X_POS_Z = 7,
    CHUNK_NEIGHBOR_CENTER = 8,
    CHUNK_NUM_NEIGHBORS = 9
} GSVoxelNeighborIndex;

typedef enum {
    Set,
    BitwiseOr,
    BitwiseAnd
} GSVoxelBitwiseOp;
