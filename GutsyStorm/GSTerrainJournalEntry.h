//
//  GSTerrainJournalEntry.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/16/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVoxel.h"
#import "GSBoxedVector.h"

@interface GSTerrainJournalEntry : NSObject <NSCoding>

@property (nonatomic) GSVoxel value;
@property (nonatomic) GSVoxelBitwiseOp operation;
@property (nonatomic, nonnull, copy) GSBoxedVector *position;

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;
- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)decoder;

@end
