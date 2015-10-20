//
//  GSOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreVideo/CVDisplayLink.h>
#import "GLString.h"

@class GSViewController;

@interface GSOpenGLView : NSOpenGLView

@property (nonatomic, weak) GSViewController *viewController;

- (void)shutdown;
- (void)setFrameRateLabel:(NSString *)label;

@end
