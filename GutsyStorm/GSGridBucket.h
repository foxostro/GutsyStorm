//
//  GSGridBucket.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/27/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSReaderWriterLock.h"

@interface GSGridBucket : NSObject

@property (nonnull, readonly, nonatomic) NSString *name;
@property (nonnull, readonly, nonatomic) NSMutableArray<NSObject <GSGridItem> *> *items;
@property (nonnull, readonly, nonatomic) NSLock *lock;

- (nonnull instancetype)init NS_UNAVAILABLE;
- (nonnull instancetype)initWithName:(nonnull NSString *)name NS_DESIGNATED_INITIALIZER;

@end
