//
//  GLKVector3.c
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <math.h>
#import <GLKit/GLKMath.h>
#import "GLKVector3Extra.h"


NSUInteger GLKVector3Hash(GLKVector3 v)
{
    // Source: <http://www.cse.yorku.ca/~oz/hash.html>
    
    NSUInteger hash = 0;
    
    for(size_t i = 0; i < sizeof(GLKVector3); ++i)
    {
        hash = ((const char *)&v)[i] + (hash << 6) + (hash << 16) - hash;
    }
    
    return hash;
}