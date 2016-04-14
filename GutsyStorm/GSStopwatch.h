//
//  GSStopwatch.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef GSStopwatch_h
#define GSStopwatch_h

#import <mach/mach.h>
#import <mach/mach_time.h>
#import <libkern/OSAtomic.h>


#define LOG_PERF 0


struct GSStopwatchBreadcrumb
{
    uint64_t startTime;
    uint64_t intermediateTime;
    OSSpinLock lock;
};


static inline uint64_t GSStopwatchStart()
{
    return mach_absolute_time();
}

static inline uint64_t GSStopwatchEnd(uint64_t startAbs)
{
    static mach_timebase_info_data_t sTimebaseInfo;
    static dispatch_once_t onceToken;
    
    uint64_t endAbs = mach_absolute_time();
    uint64_t elapsedAbs = endAbs - startAbs;
    
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&(sTimebaseInfo));
    });
    assert(sTimebaseInfo.denom != 0);
    uint64_t elapsedNs = elapsedAbs * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return elapsedNs;
}

#if LOG_PERF
static inline void GSStopwatchTraceBegin(struct GSStopwatchBreadcrumb * _Nullable breadcrumb,
                                         NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }
    
    breadcrumb->startTime = breadcrumb->intermediateTime = GSStopwatchStart();
    breadcrumb->lock = OS_SPINLOCK_INIT;
    
    assert(format);
    
    va_list args;
    va_start(args, format);
    va_end(args);
    NSString *label = [[NSString alloc] initWithFormat:format arguments:args];

    NSLog(@"Stopwatch Breadcrumb %p: Begin ; Label = \"%@\"", (void *)breadcrumb, label);
}

static inline void GSStopwatchTraceEnd(struct GSStopwatchBreadcrumb * _Nullable breadcrumb,
                                       NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }
    
    if (!OSSpinLockTry(&breadcrumb->lock)) {
        // We expect that breadcrumbs will be used only in basically serial traces of logic. If we can't immediately
        // take this lock then some other thread is holding it at the same time, which is wrong.
        abort();
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
    
    OSSpinLockUnlock(&breadcrumb->lock);
}

static inline void GSStopwatchTrace(struct GSStopwatchBreadcrumb * _Nullable breadcrumb,
                                    NSString * _Nonnull format, ...)
{
    if (!breadcrumb) {
        return;
    }
    
    if (!OSSpinLockTry(&breadcrumb->lock)) {
        // We expect that breadcrumbs will be used only in basically serial traces of logic. If we can't immediately
        // take this lock then some other thread is holding it at the same time, which is wrong.
        abort();
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
    
    OSSpinLockUnlock(&breadcrumb->lock);
}
#else
#define GSStopwatchTrace(...)
#define GSStopwatchTraceBegin(...)
#define GSStopwatchTraceEnd(...)
#endif // LOG_PERF

#endif /* GSStopwatch_h */
