//
//  Vertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 12/26/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#ifndef GutsyStorm_Vertex_h
#define GutsyStorm_Vertex_h

struct vertex
{
    GLfloat position[3];
    GLubyte color[4];
    GLbyte normal[3];
    GLshort texCoord[3];
};

#endif
