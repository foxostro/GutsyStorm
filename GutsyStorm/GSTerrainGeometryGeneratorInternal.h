//
//  GSTerrainGeometryGeneratorInternal.h
//  GutsyStorm
//
//  Created by Andrew Fox on 6/5/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainGeometryGenerator.h"


typedef enum {
    TOP,
    BOTTOM,
    NORTH,
    EAST,
    SOUTH,
    WEST,
    NUM_CUBE_FACES
} GSCubeFace;


static const int NUM_CUBE_EDGES = 12;
static const int NUM_CUBE_VERTS = 8;
static const float L = 0.5f;
static const vector_float3 LLL = (vector_float3){L, L, L};
