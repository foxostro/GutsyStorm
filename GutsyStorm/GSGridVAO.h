//
//  GSGridVAO.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSGrid.h"

typedef void (^GSVAOInvalidationNotificationBlock)(void);

@interface GSGridVAO : GSGrid<GSChunkVAO *>

@property (nonatomic, copy, nonnull) GSVAOInvalidationNotificationBlock invalidationNotification;

@end