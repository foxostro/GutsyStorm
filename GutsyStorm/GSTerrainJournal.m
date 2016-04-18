//
//  GSTerrainJournal.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/16/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainJournal.h"

@implementation GSTerrainJournal

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _journalEntries = [NSMutableArray new];
    }
    return self;
}

- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)decoder
{
    NSParameterAssert(decoder);

    if (self = [self init]) {
        _randomSeed = [decoder decodeIntegerForKey:@"randomSeed"];
        _journalEntries = [decoder decodeObjectForKey:@"journalEntries"];
    }

    return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)encoder
{
    NSParameterAssert(encoder);
    [encoder encodeInteger:self.randomSeed forKey:@"randomSeed"];
    [encoder encodeObject:self.journalEntries forKey:@"journalEntries"];
}

- (void)addEntry:(GSTerrainJournalEntry *)entry
{
    NSParameterAssert(entry);
    [self.journalEntries addObject:entry];
    BOOL success = [NSKeyedArchiver archiveRootObject:self toFile:[self.url path]];
    if (!success) {
        [NSException raise:NSGenericException format:@"Unable to recover after failing to save journal."];
    }
}

@end
