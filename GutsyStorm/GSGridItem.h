//
//  GSGridItem.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/12/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

@protocol GSGridItem <NSObject>

@required

/* The minimum corner of the item, which is a rectangular prism (box). */
@property (readonly, nonatomic) GLKVector3 minP;

@optional

/* Returns a filename to uniquely identify an item at the specified minP.
 * There must be a one-to-one mapping between minP vectors, filenames, and items of the implementing type.
 */
+ (NSString *)fileNameForItemAtMinP:(GLKVector3)minP;

/* Creates a new item at the specified minP and initializes it from file.
 * File I/O is performed asynchronously on the specified queue, and the new object is returned through the completion handler block.
 * On error, the completion handler has anItem==nil and `error' provides details about the failure.
 */
+ (void)newItemFromFile:(NSURL *)url
                   minP:(GLKVector3)minP
                  queue:(dispatch_queue_t)queue
      completionHandler:(void (^)(id anItem, NSError *error))completionHandler;

/* Save the contents of the item to specified file URL. */
- (void)saveToFile:(NSURL *)url;

@end

/* This block defines a factory to generate new grid item objects given only the unique minP of the item. */
typedef NSObject <GSGridItem> * (^grid_item_factory_t)(GLKVector3 minP);