//
//  FoxGridEdit.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/10/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <simd/simd.h>

@interface FoxGridEdit : NSObject

@property (nonatomic, strong) id originalObject;
@property (nonatomic, strong) id modifiedObject;
@property (nonatomic, assign) vector_float3 pos;

- (instancetype)initWithOriginalItem:(id)item
                        modifiedItem:(id)replacement
                                 pos:(vector_float3)p;

@end
