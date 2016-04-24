//
//  GSGridEdit.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/10/15.
//  Copyright © 2015-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

// XXX: not much uses GSGridEdit. Can the class be removed?
@interface GSGridEdit : NSObject

@property (nonatomic, strong, nullable) id originalObject;
@property (nonatomic, strong, nullable) id modifiedObject;
@property (nonatomic, assign) vector_float3 pos;

- (nonnull instancetype)initWithOriginalItem:(nullable id)item
                                 modifiedItem:(nullable id)replacement
                                          pos:(vector_float3)p;

@end
