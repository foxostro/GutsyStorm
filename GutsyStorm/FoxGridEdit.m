//
//  FoxGridEdit.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/10/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import "FoxGridEdit.h"

@implementation FoxGridEdit

- (instancetype)initWithOriginalItem:(id)item
                        modifiedItem:(id)replacement
                                 pos:(vector_float3)p
{
    self = [super init];
    if (self) {
        _originalObject = item;
        _modifiedObject = replacement;
        _pos = p;
    }
    return self;
}

@end
