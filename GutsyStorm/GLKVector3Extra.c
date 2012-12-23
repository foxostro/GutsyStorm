//
//  GLKVector3.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#include <stdio.h>
#include <math.h>
#include <GLKit/GLKMath.h>
#include "GLKVector3Extra.h"


size_t GLKVector3Hash(GLKVector3 v)
{
    // Source: <http://www.cse.yorku.ca/~oz/hash.html>
    
    size_t hash = 0;
    
    for(size_t i = 0; i < sizeof(GLKVector3); ++i)
    {
        hash = ((const char *)&v)[i] + (hash << 6) + (hash << 16) - hash;
    }
    
    return hash;
}