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

@synthesize window;
@synthesize terrain;
@synthesize displayLink;

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        terrain = nil;
    }
    
    return self;
}

- (void)dealloc
{
    [terrain release];
    CVDisplayLinkRelease(displayLink);
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [terrain sync];
    CVDisplayLinkStop(displayLink);
}

- (void)setDisplayLink:(CVDisplayLinkRef)_displayLink
{
    static dispatch_semaphore_t mutex;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        mutex = dispatch_semaphore_create(1);
    });
    
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER);
    displayLink = _displayLink;
    CVDisplayLinkRetain(displayLink);
    dispatch_semaphore_signal(mutex);
}

- (CVDisplayLinkRef)displayLink
{
    return displayLink;
}

@end
