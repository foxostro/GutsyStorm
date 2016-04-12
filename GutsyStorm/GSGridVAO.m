//
//  GSGridVAO.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"
#import "GSChunkVAO.h"
#import "GSGridVAO.h"

@implementation GSGridVAO

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                             factory:(nonnull GSGridItemFactory)factory
{
    if (self = [super initWithName:name factory:factory]) {
        self.invalidationNotification = ^{ /* do nothing */ };
    }
    return self;
}

- (void)willInvalidateItemAtPoint:(vector_float3)p
{
    self.invalidationNotification();
}

@end
