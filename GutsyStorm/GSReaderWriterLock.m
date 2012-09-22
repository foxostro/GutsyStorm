//
//  GSReaderWriterLock.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/23/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import "GSReaderWriterLock.h"

@implementation GSReaderWriterLock

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        mutex = dispatch_semaphore_create(1);
        writing = dispatch_semaphore_create(1);
        readcount = 0;
    }
    
    return self;
}


- (void)dealloc
{
    dispatch_release(mutex);
    dispatch_release(writing);
    [super dealloc];
}


- (BOOL)tryLockForReading;
{
    BOOL success = YES;
    
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER);

    readcount++;
    
    if(1 == readcount) {
        if(0 != dispatch_semaphore_wait(writing, DISPATCH_TIME_NOW)) {
            // There is a writer holding the lock right now.
            readcount--;
            success = NO;
        }
    }
    
    dispatch_semaphore_signal(mutex);
    
    return success;
}


- (void)lockForReading
{
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER);
    
    readcount++;
    
    if(1 == readcount) {
        dispatch_semaphore_wait(writing, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_semaphore_signal(mutex);
}


- (void)unlockForReading
{
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER);
    
    readcount--;
    
    if(0 == readcount) {
        dispatch_semaphore_signal(writing);
    }
    
    dispatch_semaphore_signal(mutex);    
}


- (void)lockForWriting
{
    dispatch_semaphore_wait(writing, DISPATCH_TIME_FOREVER);
}


- (void)unlockForWriting
{
    dispatch_semaphore_signal(writing);
}

@end
