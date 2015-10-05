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

- (instancetype)initWithFactory:(grid_item_factory_t)factory
{
    if (self = [super initWithFactory:factory]) {
        self.invalidationNotification = ^{ /* do nothing */ };
    }
    return self;
}

- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(GLKVector3)p
{
    self.invalidationNotification();
}

@end
