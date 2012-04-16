//
//  GSVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSBoxedVector.h"

@interface GSVertex : NSObject
{
	GSBoxedVector *position;
	GSBoxedVector *normal;
	GSBoxedVector *texCoord;
}

@property (retain, nonatomic) GSBoxedVector *position;
@property (retain, nonatomic) GSBoxedVector *normal;
@property (retain, nonatomic) GSBoxedVector *texCoord;

- (id)initWithPosition:(GSBoxedVector *)position
				normal:(GSBoxedVector *)normal
			  texCoord:(GSBoxedVector *)texCoord;
- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToVertex:(GSVertex *)vector;
- (NSUInteger)hash;
- (NSString *)toString;

@end
