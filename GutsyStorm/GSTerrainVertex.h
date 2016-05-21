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
