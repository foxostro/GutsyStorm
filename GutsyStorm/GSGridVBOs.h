//
//  GSGridVBOs.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"

typedef void (^vbo_invalidation_notification_t)(void);

@interface GSGridVBOs : GSGrid<FoxChunkVBOs *>

@property (copy) vbo_invalidation_notification_t invalidationNotification;

@end