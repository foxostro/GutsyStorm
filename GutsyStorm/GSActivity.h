//
//  GSActivity.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef GSActivity_h
#define GSActivity_h

#import "GSStopwatch.h"

struct GSStopwatchBreadcrumb
{
    uint64_t startTime;
    uint64_t intermediateTime;
};

void GSStopwatchTraceBegin(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...);
void GSStopwatchTraceEnd(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...);
void GSStopwatchTrace(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...);

#endif /* GSActivity_h */
