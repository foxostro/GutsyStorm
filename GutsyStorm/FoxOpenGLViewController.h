//
//  FoxOpenGLViewController.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "FoxOpenGLView.h"

@interface FoxOpenGLViewController : NSViewController<FoxOpenGLViewDelegate>

- (void)openGLView:(nonnull FoxOpenGLView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInOpenGLView:(nonnull FoxOpenGLView *)view;

@end