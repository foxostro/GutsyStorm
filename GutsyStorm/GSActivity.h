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

struct GSStopwatchTraceState;

struct GSStopwatchTraceState * _Nullable GSStopwatchTraceBegin(NSString * _Nonnull format, ...);
uint64_t GSStopwatchTraceEnd(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...);
void GSStopwatchTraceJoin(struct GSStopwatchTraceState * _Nullable mainTrace,
                          struct GSStopwatchTraceState * _Nullable subTrace,
                          NSString * _Nonnull format, ...);
void GSStopwatchTraceStep(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...);

#endif /* GSActivity_h */
