//
//  GSOldGrid.h
//  GutsyStorm
//
//  Created by Andrew Fox on 9/23/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"
#import "GSReaderWriterLock.h"

@interface GSOldGrid : NSObject

- (id)initWithActiveRegionArea:(size_t)areaXZ;

// Returns the object corresponding to the given point on the grid. The given factory can create that object, if necessary.
- (id)objectAtPoint:(GLKVector3)p
      objectFactory:(grid_item_factory_t)factory;

/* Tries to get the object corresponding to the given point on the grid, returning it in 'object'. The given factory can create
 * that object, if necessary. On success, 'object' points to the desired object and this method returns YES. On failure, this
 * method return NO and 'object' is not modified.
 * The method may fail if getting the object would require blocking to take a lock.
 */
- (BOOL)tryToGetObjectAtPoint:(GLKVector3)p
                       object:(id *)object
                objectFactory:(grid_item_factory_t)factory;

@end