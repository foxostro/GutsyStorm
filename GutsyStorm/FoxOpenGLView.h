//
//  FoxOpenGLView.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012-2015 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class FoxOpenGLView;


@protocol FoxOpenGLViewDelegate <NSObject>

- (void)openGLView:(nonnull FoxOpenGLView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInOpenGLView:(nonnull FoxOpenGLView *)view;

@end


@interface FoxOpenGLView : NSOpenGLView

@property (nonatomic, weak) id<FoxOpenGLViewDelegate> delegate;

- (void)shutdown;
- (void)setFrameRateLabel:(nonnull NSString *)label;

@end