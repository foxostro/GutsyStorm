//
//  FoxGridVBOs.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGrid.h"
#import "FoxChunkVBOs.h"
#import "FoxGridVBOs.h"

@implementation FoxGridVBOs

- (instancetype)initWithName:(NSString *)name factory:(fox_grid_item_factory_t)factory
{
    if (self = [super initWithName:name factory:factory]) {
        self.invalidationNotification = ^{ /* do nothing */ };
    }
    return self;
}

- (void)willInvalidateItem:(NSObject <FoxGridItem> *)item atPoint:(vector_float3)p
{
    self.invalidationNotification();
}

@end
