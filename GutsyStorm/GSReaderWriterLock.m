//
//  GSReaderWriterLock.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/23/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSReaderWriterLock.h"

@implementation GSReaderWriterLock
{
    dispatch_semaphore_t _mutex;
    dispatch_semaphore_t _writing;
    unsigned _readcount;
}


- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _mutex = dispatch_semaphore_create(1);
        _writing = dispatch_semaphore_create(1);
        _readcount = 0;
    }
    
    return self;
}


- (void)dealloc
{
    dispatch_release(_mutex);
    dispatch_release(_writing);
    [super dealloc];
}


- (BOOL)tryLockForReading
{
    BOOL success = YES;
    
    if(0 != dispatch_semaphore_wait(_mutex, DISPATCH_TIME_NOW)) {
        return NO;
    }

    _readcount++;
    
    if(1 == _readcount) {
        if(0 != dispatch_semaphore_wait(_writing, DISPATCH_TIME_NOW)) {
            // There is a writer holding the lock right now.
            _readcount--;
            success = NO;
        }
    }
    
    dispatch_semaphore_signal(_mutex);
    
    return success;
}


- (void)lockForReading
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);
    
    _readcount++;
    
    if(1 == _readcount) {
        dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_semaphore_signal(_mutex);
}


- (void)unlockForReading
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);
    
    _readcount--;
    
    if(0 == _readcount) {
        dispatch_semaphore_signal(_writing);
    }
    
    dispatch_semaphore_signal(_mutex);    
}


- (BOOL)tryLockForWriting
{
    return 0 == dispatch_semaphore_wait(_writing, DISPATCH_TIME_NOW);
}


- (void)lockForWriting
{
    dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);
}


- (void)unlockForWriting
{
    dispatch_semaphore_signal(_writing);
}

@end
