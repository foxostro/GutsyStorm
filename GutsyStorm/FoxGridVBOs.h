//
//  FoxGridVBOs.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxGrid.h"

@interface FoxGridVBOs : FoxGrid

@property (copy) void (^invalidationNotification)(void);

@end