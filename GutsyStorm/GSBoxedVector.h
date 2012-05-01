//
//  GSBoxedVector.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"

@interface GSBoxedVector : NSObject
{
    GSVector3 vector;
    NSUInteger cachedHash;
}

- (id)initWithVector:(GSVector3)vector;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVector:(GSBoxedVector *)vector;
- (NSUInteger)hash;
- (NSString *)toString;
- (GSVector3)getVector;
- (void)setVector:(GSVector3)v;

@end
