//
//  GSGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSGridEdit.h"
#import "GSReaderWriterLock.h"


@class GSBoxedVector;
typedef NSObject <GSGridItem> * _Nonnull (^GSGridTransform)(NSObject <GSGridItem> * _Nonnull original);


@interface GSGrid<__covariant TYPE> : NSObject

/* Name of the table for debugging purposes. */
@property (nonnull, readonly, nonatomic) NSString *name;

/* Specify a desired cost limit for all items in the grid. */
@property (nonatomic) NSInteger costLimit;

/* Format costs for display. */
@property (nonatomic, retain, nullable) NSFormatter *costFormatter;

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                             factory:(nonnull GSGridItemFactory)factory NS_DESIGNATED_INITIALIZER;

/* Returns the object corresponding to the given point on the grid. Creates the object from the factory, if necessary. */
- (TYPE _Nonnull)objectAtPoint:(vector_float3)p;

/* Tries to get the object corresponding to the given point on the grid, returning it in "object".
 *
 * On success, "object" points to the desired object and this method returns YES.
 * On failure, this method returns NO and "object" is not modified.
 *
 * If the object is not present in the grid cache and "createIfMissing" is YES then the factory will create the object.
 * However, if the object is not present and "createIfMissing" is NO then the method will fail.
 *
 * The method may fail if getting the object would require blocking to take a lock. This behavior is specified via
 * "blocking".
 */
- (BOOL)objectAtPoint:(vector_float3)p
             blocking:(BOOL)blocking
               object:(TYPE _Nonnull * _Nullable)object
      createIfMissing:(BOOL)createIfMissing;

/* Evicts the cached item at the given point on the grid, but does not invalidate the item or affect dependent grids. */
- (void)evictItemAtPoint:(vector_float3)p;

/* Evicts all items in the grid. (For example, to evict all items when the system comes under memory pressure.) */
- (void)evictAllItems;

/* Invalidates the item at the given point on the grid. This causes it to be evicted from the cache. Dependent grids are
 * notified that the item has been invalidated.
 */
- (void)invalidateItemWithChange:(nonnull GSGridEdit *)change
                           queue:(nonnull dispatch_queue_t)queue
                           group:(nonnull dispatch_group_t)group;

/* Method is called when the grid is just about to invalidate an item.
 * Sub-classes should override this to get custom behavior on item invalidation.
 * For example, a sub-class may wish to delete on-disk caches for items which are currently evicted and are now invalid.
 */
- (void)willInvalidateItemAtPoint:(vector_float3)p;

/* The specified change to the grid causes certain items to be invalidated in dependent grids. */
- (void)invalidateItemsInDependentGridsWithChange:(nonnull GSGridEdit *)change
                                            queue:(nonnull dispatch_queue_t)queue
                                            group:(nonnull dispatch_group_t)group;

/* Registers a grid which depends on this grid. The specified mapping function takes a point in this grid and returns
 * the points in 'dependentGrid' which actually depend on that point.
 */
- (void)registerDependentGrid:(nonnull GSGrid *)dependentGrid
                      mapping:(NSSet<GSBoxedVector *> * _Nonnull (^ _Nonnull)(GSGridEdit * _Nonnull))mapping;

/* Applies the given transformation function to the item at the specified point.
 * This function returns a new grid item which is then inserted into the grid at the same position.
 */
- (void)replaceItemAtPoint:(vector_float3)p
                     queue:(nonnull dispatch_queue_t)queue
                     group:(nonnull dispatch_group_t)group
                 transform:(nonnull GSGridTransform)fn;

/* Set the cost limit to the current cost of items in the grid. This prevents the grid cost from growing. */
- (void)capCosts;

/* Return a string description of the grid. */
- (nonnull NSString *)description;

@end