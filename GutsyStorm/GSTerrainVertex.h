//
//  GSTerrainVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct
{
    GLfloat position[3];
    GLubyte color[4];
    GLshort texCoord[3];
    GLbyte normal[3];
} GSTerrainVertex;

typedef struct
{
    GLfloat position[3];
    GLubyte color[4];
    GLshort texCoord[3];
} GSTerrainVertexNoNormal;

_Static_assert(offsetof(GSTerrainVertexNoNormal, position) == offsetof(GSTerrainVertex, position),
               "GSTerrainVertexNoNormal and GSTerrainVertex must have similar layouts");
_Static_assert(offsetof(GSTerrainVertexNoNormal, color) == offsetof(GSTerrainVertex, color),
               "GSTerrainVertexNoNormal and GSTerrainVertex must have similar layouts");
_Static_assert(offsetof(GSTerrainVertexNoNormal, texCoord) == offsetof(GSTerrainVertex, texCoord),
               "GSTerrainVertexNoNormal and GSTerrainVertex must have similar layouts");