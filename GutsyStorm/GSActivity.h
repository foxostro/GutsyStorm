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

struct GSStopwatchTraceState
{
    uint64_t startTime;
    uint64_t intermediateTime;
};

void GSStopwatchTraceBegin(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...);
void GSStopwatchTraceEnd(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...);
void GSStopwatchTraceStep(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...);

#endif /* GSActivity_h */
