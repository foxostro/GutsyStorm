//
//  GSActivity.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSActivity.h"

void GSStopwatchTraceBegin(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...)
{
    if (!trace) {
        return;
    }

    assert(format);
    
    trace->startTime = trace->intermediateTime = GSStopwatchStart();
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    NSLog(@"Trace %p: Begin %@", (void *)trace, label);
}

void GSStopwatchTraceEnd(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...)
{
    if (!trace) {
        return;
    }
    
    assert(format);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeIntermediateNs = GSStopwatchEnd(trace->intermediateTime);
    uint64_t elapsedTimeTotalNs = GSStopwatchEnd(trace->startTime);
    
    NSLog(@"Trace %p: (+%.3f ms) End %@ ; Total elapsed time is %.3f ms",
          (void *)trace,
          elapsedTimeIntermediateNs / (float)NSEC_PER_MSEC,
          label,
          elapsedTimeTotalNs / (float)NSEC_PER_MSEC);
}

void GSStopwatchTraceStep(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...)
{
    if (!trace) {
        return;
    }
    
    assert(format);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeNs = GSStopwatchEnd(trace->intermediateTime);
    NSLog(@"Trace %p: (+%.3f ms) %@",
          (void *)trace, elapsedTimeNs / (float)NSEC_PER_MSEC, label);
    trace->intermediateTime = GSStopwatchStart();
}