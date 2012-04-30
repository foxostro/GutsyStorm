//
//  GSAABB.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <assert.h>
#import "GSAABB.h"

@implementation GSAABB

@synthesize mins;
@synthesize maxs;


- (id)initWithVerts:(GSVector3 *)vertices numVerts:(size_t)numVerts
{
    self = [super init];
    if (self) {
        // Initialization code here.
        assert(numVerts > 0);
        
        mins = vertices[0];
        maxs = vertices[0];
        
        for(size_t i = 1; i < numVerts; ++i)
        {
            mins.x = MIN(vertices[i].x, mins.x);
            mins.y = MIN(vertices[i].y, mins.y);
            mins.z = MIN(vertices[i].z, mins.z);
            
            maxs.x = MAX(vertices[i].x, maxs.x);
            maxs.y = MAX(vertices[i].y, maxs.y);
            maxs.z = MAX(vertices[i].z, maxs.z);
        }
    }
    
    return self;
}


- (id)initWithMinP:(GSVector3)minP maxP:(GSVector3)maxP
{
    GSVector3 verts[2] = {minP, maxP};
    return [self initWithVerts:verts numVerts:2];
}


- (GSVector3)getVertex:(size_t)i
{
    switch(i)
    {
    case 0: return GSVector3_Make(mins.x, mins.y, mins.z);
    case 1: return GSVector3_Make(mins.x, mins.y, maxs.z);
    case 2: return GSVector3_Make(maxs.x, mins.y, mins.z);
    case 3: return GSVector3_Make(maxs.x, mins.y, maxs.z);
            
    case 4: return GSVector3_Make(mins.x, maxs.y, mins.z);
    case 5: return GSVector3_Make(mins.x, maxs.y, maxs.z);
    case 6: return GSVector3_Make(maxs.x, maxs.y, mins.z);
    case 7: return GSVector3_Make(maxs.x, maxs.y, maxs.z);
            
    default:
        [NSException raise:@"Bad index" format:@"Bad index in -getVertex:"];
        break;        
    }
    
    return mins; // never reached
}

@end
