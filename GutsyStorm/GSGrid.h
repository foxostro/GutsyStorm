//
//  GSGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSReaderWriterLock.h"


@class GSBoxedVector;
@class GSGridEdit;
@class GSGridSlot;
typedef NSObject <GSGridItem> * _Nonnull (^GSGridTransform)(NSObject <GSGridItem> * _Nonnull original);


@interface GSGrid : NSObject

/* Name of the table for debugging purposes. */
@property (nonnull, readonly, nonatomic) NSString *name;

/* The number of slots in the grid. Pays no attention to the number of slots which actually have assigned items. */
@property (nonatomic, readonly) NSInteger count;

/* The maximum number of slots allowed in the grid. Once this limit has been exceeded, the grid may choose to evict
 * items from the grid until the count is below the limit.
 * Set to a value less than or equal to zero to disable the limit.
 */
@property (nonatomic, readwrite) NSInteger countLimit;

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithName:(nonnull NSString *)name NS_DESIGNATED_INITIALIZER;

/* Returns the grid slot corresponding to the given point on the grid. Creating it, if necessary. */
- (nonnull GSGridSlot *)slotAtPoint:(vector_float3)p;

/* Tries to get the grid slot corresponding to the given point on the grid.
 *
 * On success, returns the slot object.
 * On failure, returns nil.
 *
 * The method may fail if getting the object would require blocking to take a lock. This behavior is specified via
 * the "blocking" flag.
 */
- (nullable GSGridSlot *)slotAtPoint:(vector_float3)p blocking:(BOOL)blocking;

/* Evicts all items in the grid. (For example, to evict all items when the system comes under memory pressure.) */
- (void)evictAllItems;

/* Return a string description of the grid. */
- (nonnull NSString *)description;

@end