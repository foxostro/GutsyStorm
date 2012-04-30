//
//  GSBoxedRay.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSRay.h"

@interface GSBoxedRay : NSObject
{
    GSRay ray;
}

@property (assign, nonatomic) GSRay ray;

- (id)initWithRay:(GSRay)_ray;

@end
