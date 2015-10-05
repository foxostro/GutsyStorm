//
//  GSAppDelegate.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSAppDelegate.h"
#import "GSOpenGLView.h"
#import "GSTerrain.h"

@implementation GSAppDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
        _terrain = nil;
        _openGlView = nil;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [_openGlView shutdown];
    [_terrain shutdown];

    _terrain = nil;
    _openGlView = nil;
}

@end
