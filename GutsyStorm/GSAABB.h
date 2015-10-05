//
//  GSAABB.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSAABB : NSObject

@property (assign, nonatomic) GLKVector3 mins;
@property (assign, nonatomic) GLKVector3 maxs;

- (GLKVector3)getVertex:(size_t)i;
- (instancetype)initWithVerts:(GLKVector3 *)vertices numVerts:(size_t)numVerts;
- (instancetype)initWithMinP:(GLKVector3)minP maxP:(GLKVector3)maxP;

@end
