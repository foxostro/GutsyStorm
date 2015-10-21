//
//  FoxGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGridItem.h"
#import "FoxGridEdit.h"
#import "FoxReaderWriterLock.h"


@interface FoxGrid : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithName:(NSString *)name
                     factory:(fox_grid_item_factory_t)factory NS_DESIGNATED_INITIALIZER;

/* Returns the object corresponding to the given point on the grid. Creates the object from the factory, if necessary. */
- (id)objectAtPoint:(vector_float3)p;

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
- (BOOL)objectAtPoint:(vector_float3)p
             blocking:(BOOL)blocking
               object:(id *)object
      createIfMissing:(BOOL)createIfMissing
        didCreateItem:(BOOL *)outDidCreateItem;

// Evicts the cached item at the given point on the grid, but does not invalidate the item or affect dependent grids.
- (void)evictItemAtPoint:(vector_float3)p;

// Evicts all items in the grid. (For example, to evict all items when the system comes under memory pressure.)
- (void)evictAllItems;

/* Invalidates the item at the given point on the grid. This causes it to be evicted from the cache. Dependent grids are notified
 * that the item has been invalidated.
 */
- (void)invalidateItemWithChange:(FoxGridEdit *)change;

/* Method is called when the grid is just about to invalidate an item.
 * The item is passed in 'item' unless it is currently non-resident/evicted. In that case, 'item' will be nil.
 * Sub-classes should override this to get custom behavior on item invalidation.
 * For example, a sub-class may wish to delete on-disk caches for items which are currently evicted and are now invalid.
 */
- (void)willInvalidateItem:(NSObject <FoxGridItem> *)item atPoint:(vector_float3)p;

// The specified change to the grid causes certain items to be invalidated in dependent grids.
- (void)invalidateItemsInDependentGridsWithChange:(FoxGridEdit *)change;

/* Registers a grid which depends on this grid. The specified mapping function takes a point in this grid and returns the points in
 * 'dependentGrid' which actually depend on that point.
 */
- (void)registerDependentGrid:(FoxGrid *)dependentGrid
                      mapping:(NSSet * (^)(FoxGridEdit *))mapping;

/* Applies the given transformation function to the item at the specified point.
 * This function returns a new grid item which is then inserted into the grid at the same position.
 */
- (void)replaceItemAtPoint:(vector_float3)p
                 transform:(NSObject <FoxGridItem> * (^)(NSObject <FoxGridItem> *))fn;

@end