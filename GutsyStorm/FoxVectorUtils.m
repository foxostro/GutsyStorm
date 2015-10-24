//
//  FoxVectorUtils.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/18/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxVectorUtils.h"


NSUInteger vector_hash(vector_float3 inputVector)
{
    // We cannot permit padding bytes to affect the hash.
    vector_float3 v;
    bzero(&v, sizeof(vector_float3));
    v.xyz = inputVector.xyz;
 
    // Source: <http://www.cse.yorku.ca/~oz/hash.html>
    
    NSUInteger hash = 0;
    
    for(size_t i = 0; i < sizeof(vector_float3); ++i)
    {
        hash = ((const char *)&v)[i] + (hash << 6) + (hash << 16) - hash;
    }
    
    return hash;
}