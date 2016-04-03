//
//  GSGridVBOs.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"

typedef void (^GSVBOInvalidationNotificationBlock)(void);

@interface GSGridVBOs : GSGrid<GSChunkVAO *>

@property (nonatomic, copy, nonnull) GSVBOInvalidationNotificationBlock invalidationNotification;

@end