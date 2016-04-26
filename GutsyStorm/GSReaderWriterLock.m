//
//  GSReaderWriterLock.m
//  GutsyStorm
//
//  Created by Andrew Fox on 4/23/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSReaderWriterLock.h"
#import <pthread.h>


//#define DEBUG_LOG(...) NSLog(__VA_ARGS__)
#define DEBUG_LOG(...)


@implementation GSReaderWriterLock
{
    dispatch_semaphore_t _mutex;
    dispatch_semaphore_t _writing;
    unsigned _readcount;
    
    NSMutableArray<NSValue *> *_readers;
    pthread_t _writer;
}

- (nonnull instancetype)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
        _mutex = dispatch_semaphore_create(1);
        _writing = dispatch_semaphore_create(1);
        _readcount = 0;
        _readers = [NSMutableArray new];
        _writer = NULL;
        self.name = [super description];
    }
    return self;
}

- (BOOL)tryLockForReading
{
    BOOL success = YES;

    if(0 != dispatch_semaphore_wait(_mutex, DISPATCH_TIME_NOW)) {
        DEBUG_LOG(@"tryLockForReading: NO (%@)", self.name);
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
    
    if (success) {
        [_readers addObject:[NSValue valueWithPointer:pthread_self()]];
    }

    dispatch_semaphore_signal(_mutex);

    DEBUG_LOG(@"tryLockForReading: %d (%@)", success, self.name);
    return success;
}

- (void)lockForReading
{
    DEBUG_LOG(@"lockForReading (%@)", self.name);

    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);

    [_readers addObject:[NSValue valueWithPointer:pthread_self()]];
    _readcount++;

    if(1 == _readcount) {
        dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);
    }

    dispatch_semaphore_signal(_mutex);
}

- (void)unlockForReading
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);

    [_readers removeObjectAtIndex:[_readers indexOfObject:[NSValue valueWithPointer:pthread_self()]]];
    _readcount--;

    if(0 == _readcount) {
        dispatch_semaphore_signal(_writing);
    }

    dispatch_semaphore_signal(_mutex);

    DEBUG_LOG(@"unlockForReading (%@)", self.name);
}

- (BOOL)tryLockForWriting
{
    DEBUG_LOG(@"tryLockForWriting (%@)", self.name);
    BOOL success = !dispatch_semaphore_wait(_writing, DISPATCH_TIME_NOW);
    
    if (success) {
        dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);
        _writer = pthread_self();
        dispatch_semaphore_signal(_mutex);
    }
    
    return success;
}

- (void)lockForWriting
{
    DEBUG_LOG(@"lockForWriting (%@)", self.name);
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);

    dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);
    _writer = pthread_self();

    dispatch_semaphore_signal(_mutex);
}

- (void)unlockForWriting
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);
    _writer = NULL;
    dispatch_semaphore_signal(_mutex);
    
    dispatch_semaphore_signal(_writing);
    DEBUG_LOG(@"unlockForWriting (%@)", self.name);
}

- (void)holdingWriteLock
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);

    if (_writer != pthread_self()) {
        [NSException raise:NSInternalInconsistencyException format:@"No write scope"];
    }

    dispatch_semaphore_signal(_mutex);
}

- (void)holdingReadLock
{
    dispatch_semaphore_wait(_mutex, DISPATCH_TIME_FOREVER);
    
    if (![_readers containsObject:[NSValue valueWithPointer:pthread_self()]]) {
        [NSException raise:NSInternalInconsistencyException format:@"No read scope"];
    }
    
    dispatch_semaphore_signal(_mutex);
}

@end
