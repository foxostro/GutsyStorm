//
//  GSNewGrid.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "GSNewGrid.h"

@implementation GSNewGrid
{
    grid_item_factory_t _factory;
}

- (id)initWithFactory:(grid_item_factory_t)factory
{
    if(self = [super init]) {
        _factory = [factory copy];
    }

    return self;
}

- (id)objectAtPoint:(GLKVector3)p
{
    assert(!"unimplemented");
    return nil;
}

- (BOOL)tryToGetObjectAtPoint:(GLKVector3)p
                       object:(id *)object
{
    assert(!"unimplemented");
    return NO;
}

- (void)evictItemAtPoint:(GLKVector3)p
{
    assert(!"unimplemented");
}

- (void)evictAllItems
{
    assert(!"unimplemented");
}

- (void)invalidateItemAtPoint:(GLKVector3)p
{
    assert(!"unimplemented");
}

- (void)invalidateItemsDependentOnItemAtPoint:(GLKVector3)p
{
    assert(!"unimplemented");
}

- (void)registerDependentGrid:(GSNewGrid *)dependentGrid
                      mapping:(NSSet * (^)(GLKVector3))mapping
{
    assert(!"unimplemented");
}

- (void)replaceItemAtPoint:(GLKVector3)p
                 transform:(NSObject <GSGridItem> * (^)(NSObject <GSGridItem> *))fn
{
    assert(!"unimplemented");
}

@end