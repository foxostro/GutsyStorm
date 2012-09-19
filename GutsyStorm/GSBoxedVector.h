//
//  GSBoxedVector.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"
#import "GSIntegerVector3.h"

@interface GSBoxedVector : NSObject
{
    GSVector3 vector;
    NSUInteger cachedHash;
}

+ (GSBoxedVector *)boxedVectorWithVector:(GSVector3)vector;
+ (GSBoxedVector *)boxedVectorWithIntegerVector:(GSIntegerVector3)vector;
- (id)initWithVector:(GSVector3)vector;
- (id)initWithIntegerVector:(GSIntegerVector3)vector;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVector:(GSBoxedVector *)vector;
- (NSUInteger)hash;
- (NSString *)toString;
- (GSVector3)vectorValue;
- (GSIntegerVector3)integerVectorValue;

@end
