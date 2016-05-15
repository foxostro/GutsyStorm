//
//  GSAABB.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>

@interface GSBoxedAABB : NSObject

@property (assign, nonatomic) vector_float3 mins;
@property (assign, nonatomic) vector_float3 maxs;

- (vector_float3)getVertex:(size_t)i;
- (nonnull instancetype)initWithVerts:(nonnull vector_float3 *)vertices numVerts:(size_t)numVerts;
- (nonnull instancetype)initWithMinP:(vector_float3)minP maxP:(vector_float3)maxP;

@end
