//
//  GSAABB.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"

@interface GSAABB : NSObject
{
    GSVector3 mins, maxs;
}

@property (assign, nonatomic) GSVector3 mins;
@property (assign, nonatomic) GSVector3 maxs;

- (GSVector3)getVertex:(size_t)i;
- (id)initWithVerts:(GSVector3 *)vertices numVerts:(size_t)numVerts;
- (id)initWithMinP:(GSVector3)minP maxP:(GSVector3)maxP;

@end
