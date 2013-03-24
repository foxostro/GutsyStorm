//
//  GSNewGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSReaderWriterLock.h"

@interface GSGrid : NSObject

- (id)initWithFactory:(grid_item_factory_t)factory;

/* Returns the object corresponding to the given point on the grid. Creates the object from the factory, if necessary. */
- (id)objectAtPoint:(GLKVector3)p;

/* Tries to get the object corresponding to the given point on the grid, returning it in "object".
 *
 * On success, "object" points to the desired object and this method returns YES.
 * On failure, this method returns NO and "object" is not modified.
 *
 * If the object is not present in the grid cache and "createIfMissing" is YES then the factory will create the object.
 * However, if the object is not present and "createIfMissing" is NO then the method will fail.
 *
 * The method may fail if getting the object would require blocking to take a lock. This behavior is specified via "blocking".
 */
- (BOOL)objectAtPoint:(GLKVector3)p
             blocking:(BOOL)blocking
               object:(id *)object
      createIfMissing:(BOOL)createIfMissing;

/* Begin asynchronous generation of the item at the specified point. Cache that item when it is ready. */
- (void)prefetchItemAtPoint:(GLKVector3)p;

// Evicts the cached item at the given point on the grid, but does not invalidate the item or affect dependent grids.
- (void)evictItemAtPoint:(GLKVector3)p;

// Evicts all items in the grid. (For example, to evict all items when the system comes under memory pressure.)
- (void)evictAllItems;

/* Invalidates the item at the given point on the grid. This causes it to be evicted from the cache. Dependent grids are notified
 * that the item has been invalidated.
 */
- (void)invalidateItemAtPoint:(GLKVector3)p;

/* Method is called when the grid is just about to invalidate an item.
 * The item is passed in 'item' unless it is currently non-resident/evicted. In that case, 'item' will be nil.
 * Sub-classes should override this to get custom behavior on item invalidation.
 * For example, a sub-class may wish to delete on-disk caches for items which are currently evicted and are now invalid.
 */
- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(GLKVector3)p;

// Items in dependent grids are invalidated at points which map to the specified point in this grid.
- (void)invalidateItemsDependentOnItemAtPoint:(GLKVector3)p;

/* Registers a grid which depends on this grid. The specified mapping function takes a point in this grid and returns the points in
 * 'dependentGrid' which actually depend on that point.
 */
- (void)registerDependentGrid:(GSGrid *)dependentGrid
                      mapping:(NSSet * (^)(GLKVector3))mapping;

/* Applies the given transformation function to the item at the specified point.
 * This function returns a new grid item which is then inserted into the grid at the same position.
 */
- (void)replaceItemAtPoint:(GLKVector3)p
                 transform:(NSObject <GSGridItem> * (^)(NSObject <GSGridItem> *))fn;

@end