//
//  GSAppDelegate.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSAppDelegate.h"

@implementation GSAppDelegate
{
    CVDisplayLinkRef _displayLink;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _terrain = nil;
    }
    
    return self;
}

- (void)dealloc
{
    CVDisplayLinkRelease(_displayLink);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [_terrain sync];
    CVDisplayLinkStop(_displayLink);
}

- (void)setDisplayLink:(CVDisplayLinkRef)displayLink
{
    static dispatch_semaphore_t mutex;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        mutex = dispatch_semaphore_create(1);
    });
    
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER);
    _displayLink = displayLink;
    CVDisplayLinkRetain(_displayLink);
    dispatch_semaphore_signal(mutex);
}

- (CVDisplayLinkRef)displayLink
{
    return _displayLink;
}

@end
