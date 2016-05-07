//
//  GSTerrainJournal.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/16/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"

@implementation GSTerrainJournal
{
    dispatch_queue_t _queue;
    dispatch_group_t _group;
}

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _journalEntries = [NSMutableArray new];
        _queue = dispatch_queue_create("com.foxostro.GutsyStorm.GSTerrainJournal", DISPATCH_QUEUE_SERIAL);
        _group = dispatch_group_create();
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

- (void)flush
{
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

- (void)addEntry:(GSTerrainJournalEntry *)entry
{
    NSParameterAssert(entry);

    dispatch_group_async(_group, _queue, ^{
        // First, delete all previous journal entries which reference the modified block position. These are redundant
        // and a little bit of house keeping work spent now can drastically reduce the time spent applying the journal
        // later.
        // Counter-argument: Rebuilding from the journal is expected to be expensive and expected to be rare.
        NSMutableArray<GSTerrainJournalEntry *> *entriesToDelete =
            [[NSMutableArray alloc] initWithCapacity:self.journalEntries.count];
        for(GSTerrainJournalEntry *thatEntry in self.journalEntries)
        {
            if ([entry.position isEqualTo:thatEntry.position]) {
                [entriesToDelete addObject:thatEntry];
            }
        }
        [self.journalEntries removeObjectsInArray:entriesToDelete];
        
        [self.journalEntries addObject:entry];
        
        if (self.url) {
            BOOL success = [NSKeyedArchiver archiveRootObject:self toFile:[self.url path]];
            if (!success) {
                [NSException raise:NSGenericException format:@"Unable to recover after failing to save journal."];
            }
        }
    });
}

@end
