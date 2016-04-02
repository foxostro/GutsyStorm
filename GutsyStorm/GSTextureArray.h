//
//  GSTextureArray.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/21/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface GSTextureArray : NSObject

- (nonnull instancetype)initWithImagePath:(nonnull NSString *)path numTextures:(NSUInteger)numTextures;
- (void)bind;
- (void)unbind;

@end
