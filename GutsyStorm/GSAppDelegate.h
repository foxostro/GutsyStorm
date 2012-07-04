//
//  GSAppDelegate.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/16/12.
//  Copyright © 2012 Andrew Fox. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSChunkStore.h"


@interface GSAppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *window;
    GSChunkStore *chunkStore;
}

@property (assign) IBOutlet NSWindow *window;
@property (retain) GSChunkStore *chunkStore;

@end
