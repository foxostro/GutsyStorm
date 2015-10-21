//
//  GSViewController.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSOpenGLView.h"

@interface GSViewController : NSViewController<GSOpenGLViewDelegate>

- (void)gsOpenGLView:(GSOpenGLView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInGSOpenGLView:(GSOpenGLView *)view;

@end