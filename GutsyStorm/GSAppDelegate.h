//
//  GSAppDelegate.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSTerrain.h"


@interface GSAppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet NSWindow *window;
@property (strong) GSTerrain *terrain;
@property (assign, getter = displayLink, setter = setDisplayLink:) CVDisplayLinkRef displayLink;

- (CVDisplayLinkRef)displayLink;
- (void)setDisplayLink:(CVDisplayLinkRef)displayLink;

@end
