//
//  GSTerrainApplyJournalOperation.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/2/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>


@class GSTerrainJournal;
@class GSTerrainChunkStore;


@interface GSTerrainApplyJournalOperation : NSOperation

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                             chunkStore:(nonnull GSTerrainChunkStore *)chunkStore NS_DESIGNATED_INITIALIZER;
@end
