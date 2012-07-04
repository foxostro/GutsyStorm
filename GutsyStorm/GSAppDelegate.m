//
//  GSAppDelegate.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import "GSAppDelegate.h"

@implementation GSAppDelegate

@synthesize window;
@synthesize chunkStore;

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        chunkStore = nil;
    }
    
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}


- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [chunkStore waitForSaveToFinish];
}

@end
