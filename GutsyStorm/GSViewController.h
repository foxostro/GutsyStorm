//
//  GSViewController.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/20/15.
//  Copyright © 2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface GSViewController : NSViewController

- (void)reshapeWithBounds:(NSRect)bounds;

// The associated view is in the middle of drawing a frame.
// The OpenGL context is bound to the current thread and has been locked.
- (void)onDraw;

@end