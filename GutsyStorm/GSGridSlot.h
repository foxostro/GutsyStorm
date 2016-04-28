//
//  GSGridSlot.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/27/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>
#import "GSGridItem.h"

@class GSReaderWriterLock;

@interface GSGridSlot : NSObject

@property (nonatomic, nullable, retain) NSObject<GSGridItem> *item;
@property (nonatomic, nonnull, readonly) GSReaderWriterLock *lock;
@property (nonatomic, readonly) vector_float3 minP;

- (nonnull instancetype)init NS_UNAVAILABLE;
- (nonnull instancetype)initWithMinP:(vector_float3)mp NS_DESIGNATED_INITIALIZER;

@end
