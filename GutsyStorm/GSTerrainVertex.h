//
//  GSTerrainVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

struct GSTerrainVertex
{
    GLfloat position[3];
    GLubyte color[4];
    GLbyte normal[3];
    GLshort texCoord[3];
};
