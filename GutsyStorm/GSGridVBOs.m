//
//  GSGridVBOs.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKVector3.h>
#import "GSGrid.h"
#import "GSChunkVBOs.h"
#import "GSGridVBOs.h"

@implementation GSGridVBOs

- (instancetype)initWithName:(NSString *)name factory:(grid_item_factory_t)factory
{
    self = [super initWithName:name factory:factory];
    return self;
}

@end
