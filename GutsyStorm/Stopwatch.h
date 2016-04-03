//
//  Stopwatch.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/3/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#ifndef Stopwatch_h
#define Stopwatch_h

#if LOG_PERF
#import <mach/mach.h>
#import <mach/mach_time.h>

static inline uint64_t stopwatchStart()
{
    return mach_absolute_time();
}

static inline uint64_t stopwatchEnd(uint64_t startAbs)
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
#endif

#endif /* Stopwatch_h */
