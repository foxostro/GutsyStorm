//
//  GSGridLRU.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/9/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGridItem.h"


@class GSGridBucket;


@interface GSGridLRU : NSObject

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;

/* Mark the object as being recently used. */
- (void)referenceObject:(nonnull NSObject<NSCopying> *)object bucket:(nonnull GSGridBucket *)bucket;

/* Get the least recently used object and remove it from the LRU list. */
- (void)popAndReturnObject:(NSObject<NSCopying> * _Nonnull * _Nullable)outObject
                    bucket:(GSGridBucket * _Nonnull * _Nullable)outBucket;

/* Remove the object from the LRU list. */
- (void)removeObject:(nonnull NSObject<NSCopying> *)object;

/* Remove all objects from the LRU list. */
- (void)removeAllObjects;

@end