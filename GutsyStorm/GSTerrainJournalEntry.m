//
//  GSTerrainJournalEntry.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/16/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainJournalEntry.h"

@implementation GSTerrainJournalEntry

- (nonnull instancetype)init
{
    return self = [super init];
}

- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)decoder
{
    NSParameterAssert(decoder);
    
    if (self = [self init]) {
        _position = [decoder decodeObjectForKey:@"position"];
        _operation = (GSVoxelBitwiseOp)[decoder decodeIntegerForKey:@"operation"];
        [[decoder decodeObjectForKey:@"value"] getBytes:&_value length:sizeof(_value)];
    }
    
    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)encoder
{
    NSParameterAssert(encoder);
    
    [encoder encodeObject:self.position forKey:@"position"];
    [encoder encodeInteger:(NSInteger)self.operation forKey:@"operation"];
    [encoder encodeObject:[NSData dataWithBytes:&_value length:sizeof(_value)] forKey:@"value"];
}

@end
