//
//  GSOpenGLViewController.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSOpenGLView.h"

@interface GSOpenGLViewController : NSViewController<FoxOpenGLViewDelegate, NSApplicationDelegate>

- (void)openGLView:(nonnull GSOpenGLView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInOpenGLView:(nonnull GSOpenGLView *)view;

@end