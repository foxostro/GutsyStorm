//
//  GSTerrainJournal.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/16/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GSTerrainJournalEntry;

@interface GSTerrainJournal : NSObject <NSCoding>

@property (nonatomic) NSInteger randomSeed;
@property (nonatomic, nonnull) NSMutableArray<GSTerrainJournalEntry *> *journalEntries;
@property (nonatomic, nullable, copy) NSURL *url;

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)decoder;

- (void)addEntry:(nonnull GSTerrainJournalEntry *)entry;
- (void)flush;

@end
