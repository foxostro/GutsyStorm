//
//  GSActivity.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSActivity.h"

void GSStopwatchTraceBegin(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }

    assert(format);
    
    breadcrumb->startTime = breadcrumb->intermediateTime = GSStopwatchStart();
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    NSLog(@"Stopwatch Breadcrumb %p: Begin ; Label = \"%@\"", (void *)breadcrumb, label);
}

void GSStopwatchTraceEnd(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }
    
    assert(format);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeIntermediateNs = GSStopwatchEnd(breadcrumb->intermediateTime);
    uint64_t elapsedTimeTotalNs = GSStopwatchEnd(breadcrumb->startTime);
    
    NSLog(@"Stopwatch Breadcrumb %p: End = %.3f ms ; Total Time = %.3f\tms ; Label = \"%@\"",
          (void *)breadcrumb,
          elapsedTimeIntermediateNs / (float)NSEC_PER_MSEC,
          elapsedTimeTotalNs / (float)NSEC_PER_MSEC,
          label);
}

void GSStopwatchTrace(struct GSStopwatchBreadcrumb * _Nullable breadcrumb, NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }
    
    assert(format);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeNs = GSStopwatchEnd(breadcrumb->intermediateTime);
    NSLog(@"Stopwatch Breadcrumb %p: Elapsed = %.3f\tms ; Label = \"%@\"",
          (void *)breadcrumb, elapsedTimeNs / (float)NSEC_PER_MSEC, label);
    breadcrumb->intermediateTime = GSStopwatchStart();
}