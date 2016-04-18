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

#endif /* GSStopwatch_h */
