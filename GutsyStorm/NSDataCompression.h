//
//  NSDataCompression.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/24/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (NSDataCompression)

- (NSData *) zlibInflate;
- (NSData *) zlibDeflate;

@end