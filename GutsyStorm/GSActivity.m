//
//  GSActivity.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/17/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import "GSActivity.h"


static __thread struct GSStopwatchTraceState gTrace;
static BOOL gStopwatchTracingEnabled = NO;


void GSStopwatchTraceBegin(NSString * _Nonnull format, ...)
{
    assert(format);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gStopwatchTracingEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"StopwatchTraceEnabled"];
    });
    
    if (!gStopwatchTracingEnabled) {
        return;
    }

    gTrace.startTime = gTrace.intermediateTime = GSStopwatchStart();
    gTrace.active = YES;
    gTrace.thread = pthread_self();

    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    NSLog(@"Trace %p: Begin %@", (void *)&gTrace, label);
}

struct GSStopwatchTraceState GSStopwatchTraceEnd(NSString * _Nonnull format, ...)
{
    if (gStopwatchTracingEnabled) {
        assert(format);
        assert(gTrace.active);
        assert(pthread_self() == gTrace.thread);

        gTrace.active = NO;

        va_list args;
        va_start(args, format);
        va_end(args);
        NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
        
        uint64_t elapsedTimeIntermediateNs = GSStopwatchEnd(gTrace.intermediateTime);
        gTrace.elapsedTimeTotalNs = GSStopwatchEnd(gTrace.startTime);
        
        NSLog(@"Trace %p: (+%.3f ms) End %@ ; Total elapsed time is %.3f ms",
              (void *)&gTrace,
              elapsedTimeIntermediateNs / (float)NSEC_PER_MSEC,
              label,
              gTrace.elapsedTimeTotalNs / (float)NSEC_PER_MSEC);
    }
    
    return gTrace;
}

void GSStopwatchTraceJoin(struct GSStopwatchTraceState * _Nullable completedSubtrace)
{
    if (!gStopwatchTracingEnabled) {
        return;
    }
    
    assert(gTrace.active);
    assert(completedSubtrace && !completedSubtrace->active);
    
    GSStopwatchTraceStep(@"Join %p ; Total elapsed time of sub-trace is %.3f ms",
                         completedSubtrace, completedSubtrace->elapsedTimeTotalNs / (float)NSEC_PER_MSEC);
}

void GSStopwatchTraceStep(NSString * _Nonnull format, ...)
{
    if (!gStopwatchTracingEnabled) {
        return;
    }

    if (!gTrace.active) {
        return;
    }
    
    assert(format);
    assert(pthread_self() == gTrace.thread);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];
    
    uint64_t elapsedTimeNs = GSStopwatchEnd(gTrace.intermediateTime);
    NSLog(@"Trace %p: (+%.3f ms) %@",
          (void *)&gTrace, elapsedTimeNs / (float)NSEC_PER_MSEC, label);
    gTrace.intermediateTime = GSStopwatchStart();
}