//
//  GSGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/23/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"

@interface GSGrid : NSObject
{
    NSUInteger numBuckets;
    NSMutableArray **buckets;
    
    NSUInteger numLocks;
    NSLock **locks;
    
    //int32_t n;
}

- (id)initWithActiveRegionArea:(size_t)areaXZ;

// Returns the object corresponding to the given point on the grid. The given factory can create that object, if necessary.
- (id)objectAtPoint:(GSVector3)p objectFactory:(id (^)(GSVector3 minP))factory;

@end
