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

/* Specify a desired cost limit for all items in the grid. */
@property (nonatomic) NSInteger costLimit;

/* Format costs for display. */
@property (nonatomic, retain, nullable) NSFormatter *costFormatter;

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