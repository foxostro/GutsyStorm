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


@interface GSGridLRU<__covariant TYPE> : NSObject

- (nonnull instancetype)init NS_DESIGNATED_INITIALIZER;

/* Mark the object as being recently used. */
- (void)referenceObject:(TYPE _Nonnull)object bucket:(nonnull GSGridBucket *)bucket;

/* Get the least recently used object and remove it from the LRU list. */
- (void)popAndReturnObject:(TYPE _Nullable * _Nonnull)outObject bucket:(GSGridBucket * _Nonnull * _Nonnull)outBucket;

/* Remove the object from the LRU list. */
- (void)removeObject:(TYPE _Nonnull)object;

/* Remove all objects from the LRU list. */
- (void)removeAllObjects;

@end