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

- (nonnull instancetype)initWithName:(NSString *)name
{
    if (self = [super init]) {
        _name = [name copy];
        _lock = [[GSReaderWriterLock alloc] init];
        _lock.name = [NSString stringWithFormat:@"%@.lock", name];
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

@end
