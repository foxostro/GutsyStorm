//
//  GSTerrainApplyJournalOperation.m
//  GutsyStorm
//
//  Created by Andrew Fox on 5/2/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSTerrainApplyJournalOperation.h"
#import "GSTerrainJournal.h"
#import "GSTerrainJournalEntry.h"
#import "GSTerrainChunkStore.h"
#import "GSTerrainModifyBlockOperation.h"


@implementation GSTerrainApplyJournalOperation
{
    GSTerrainJournal *_journal;
    GSTerrainChunkStore *_chunkStore;
}

- (nonnull instancetype)init
{
    @throw nil;
}

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                             chunkStore:(nonnull GSTerrainChunkStore *)chunkStore
{
    NSParameterAssert(journal);
    NSParameterAssert(chunkStore);

    if (self = [super init]) {
        _journal = journal;
        _chunkStore = chunkStore;
    }
    return self;
}

- (void)main
{
    _chunkStore.enableLoadingFromCacheFolder = NO;

    for(GSTerrainJournalEntry *entry in _journal.journalEntries)
    {
        GSTerrainModifyBlockOperation *op;
        op = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                 block:entry.value
                                                             operation:Set
                                                              position:[entry.position vectorValue]
                                                               journal:nil];
        [op main];
    }
    
    [_chunkStore flushSaveQueue];
    _chunkStore.enableLoadingFromCacheFolder = YES;
}

@end
