//
//  GSBoxedTerrainVertex.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/15/12.
//  Copyright 2012-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "GSTerrainVertex.h"

@interface GSBoxedTerrainVertex : NSObject

@property (assign, nonatomic) GSTerrainVertex v;

+ (GSBoxedTerrainVertex *)vertexWithPosition:(vector_float3)position
                                      normal:(vector_long3)normal
                                    texCoord:(vector_long3)texCoord;

+ (GSBoxedTerrainVertex *)vertexWithVertex:(GSTerrainVertex *)pv;

- (instancetype)initWithVertex:(GSTerrainVertex *)pv;

- (instancetype)initWithPosition:(vector_float3)position
                          normal:(vector_long3)normal
                        texCoord:(vector_long3)texCoord;

- (vector_float3)position;

@end
