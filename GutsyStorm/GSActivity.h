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
#import <pthread.h>


struct GSStopwatchTraceState
{
    uint64_t startTime;
    uint64_t intermediateTime;
    uint64_t elapsedTimeTotalNs;
    BOOL active;
    pthread_t _Nullable thread;
};


void GSStopwatchTraceBegin(NSString * _Nonnull format, ...);
struct GSStopwatchTraceState GSStopwatchTraceEnd(NSString * _Nonnull format, ...);
void GSStopwatchTraceJoin(struct GSStopwatchTraceState * _Nullable completedSubtrace);
void GSStopwatchTraceStep(NSString * _Nonnull format, ...);

#endif /* GSActivity_h */
