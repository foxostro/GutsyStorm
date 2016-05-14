//
//  GSTerrainModifyBlockBenchmark.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/13/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSTerrainModifyBlockBenchmark : NSObject

- (nonnull instancetype)init NS_UNAVAILABLE;
- (nonnull instancetype)initWithOpenGLContext:(nonnull NSOpenGLContext *)context NS_DESIGNATED_INITIALIZER;
- (void)run;

@end
