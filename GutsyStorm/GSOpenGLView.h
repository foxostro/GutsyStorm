//
//  GSOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class GSOpenGLView;


@protocol GSOpenGLViewDelegate <NSObject>

- (void)gsOpenGLView:(GSOpenGLView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInGSOpenGLView:(GSOpenGLView *)view;

@end


@interface GSOpenGLView : NSOpenGLView

@property (nonatomic, weak) id<GSOpenGLViewDelegate> delegate;

- (void)shutdown;
- (void)setFrameRateLabel:(NSString *)label;

@end