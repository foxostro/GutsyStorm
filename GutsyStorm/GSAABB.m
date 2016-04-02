//
//  GSAABB.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import "GSAABB.h"

@implementation GSAABB

- (nonnull instancetype)initWithVerts:(nonnull vector_float3 *)vertices numVerts:(size_t)numVerts
{
    self = [super init];
    if (self) {
        // Initialization code here.
        assert(numVerts > 0);
        
        _mins = vertices[0];
        _maxs = vertices[0];
        
        for(size_t i = 1; i < numVerts; ++i)
        {
            _mins.x = MIN(vertices[i].x, _mins.x);
            _mins.y = MIN(vertices[i].y, _mins.y);
            _mins.z = MIN(vertices[i].z, _mins.z);
            
            _maxs.x = MAX(vertices[i].x, _maxs.x);
            _maxs.y = MAX(vertices[i].y, _maxs.y);
            _maxs.z = MAX(vertices[i].z, _maxs.z);
        }
    }
    
    return self;
}

- (nonnull instancetype)initWithMinP:(vector_float3)minP maxP:(vector_float3)maxP
{
    vector_float3 verts[2] = {minP, maxP};
    return [self initWithVerts:verts numVerts:2];
}

- (vector_float3)getVertex:(size_t)i
{
    switch(i)
    {
        case 0: return (vector_float3){_mins.x, _mins.y, _mins.z};
        case 1: return (vector_float3){_mins.x, _mins.y, _maxs.z};
        case 2: return (vector_float3){_maxs.x, _mins.y, _mins.z};
        case 3: return (vector_float3){_maxs.x, _mins.y, _maxs.z};
            
        case 4: return (vector_float3){_mins.x, _maxs.y, _mins.z};
        case 5: return (vector_float3){_mins.x, _maxs.y, _maxs.z};
        case 6: return (vector_float3){_maxs.x, _maxs.y, _mins.z};
        case 7: return (vector_float3){_maxs.x, _maxs.y, _maxs.z};

    default:
        [NSException raise:@"Bad index" format:@"Bad index in -getVertex:"];
        break;
    }

    return _mins; // never reached
}

@end
