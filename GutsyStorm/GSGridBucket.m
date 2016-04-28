//
//  GSGridBucket.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/27/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSGridBucket.h"
#import "GSReaderWriterLock.h"

@implementation GSGridBucket

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithName:(NSString *)name
{
    if (self = [super init]) {
        _name = [name copy];
        _items = [[NSMutableArray alloc] init];
        _lock = [[NSLock alloc] init];
        _lock.name = [NSString stringWithFormat:@"%@.lock", name];
    }
    return self;
}

@end
