//
//  GSActivity.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSActivity.h"


struct GSStopwatchTraceState
{
    uint64_t startTime;
    uint64_t intermediateTime;
    OSSpinLock lock;
};


static BOOL gStopwatchTracingEnabled = NO;


struct GSStopwatchTraceState * _Nullable GSStopwatchTraceBegin(NSString * _Nonnull format, ...)
{
    assert(format);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gStopwatchTracingEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"StopwatchTraceEnabled"];
    });
    
    if (!gStopwatchTracingEnabled) {
        return NULL;
    }
    
    struct GSStopwatchTraceState *trace = calloc(1, sizeof(struct GSStopwatchTraceState));

    trace->startTime = trace->intermediateTime = GSStopwatchStart();
    trace->lock = OS_SPINLOCK_INIT;

    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    NSLog(@"Trace %p: Begin %@", (void *)trace, label);
    
    return trace;
}

uint64_t GSStopwatchTraceEnd(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...)
{
    assert(format);

    if (!trace) {
        return 0;
    }
    
    if (!gStopwatchTracingEnabled) {
        return 0;
    }
    
    OSSpinLockLock(&trace->lock);
    
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
    
    free(trace);
    
    return elapsedTimeTotalNs;
}

void GSStopwatchTraceJoin(struct GSStopwatchTraceState * _Nullable mainTrace,
                          struct GSStopwatchTraceState * _Nullable subTrace,
                          NSString * _Nonnull format, ...)
{
    assert(format);
    
    if (!mainTrace || !subTrace) {
        return;
    }
    
    if (!gStopwatchTracingEnabled) {
        return;
    }

    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeTotalNs = GSStopwatchTraceEnd(subTrace, label);

    GSStopwatchTraceStep(mainTrace, @"Join %p ; Total elapsed time of sub-trace is %.3f ms",
                         subTrace, elapsedTimeTotalNs / (float)NSEC_PER_MSEC);
}

void GSStopwatchTraceStep(struct GSStopwatchTraceState * _Nullable trace, NSString * _Nonnull format, ...)
{
    assert(format);

    if (!trace) {
        return;
    }
    
    OSSpinLockLock(&trace->lock);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeNs = GSStopwatchEnd(trace->intermediateTime);
    NSLog(@"Trace %p: (+%.3f ms) %@",
          (void *)trace, elapsedTimeNs / (float)NSEC_PER_MSEC, label);
    trace->intermediateTime = GSStopwatchStart();
    
    OSSpinLockUnlock(&trace->lock);
}