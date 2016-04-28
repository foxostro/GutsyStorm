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
    NSMutableArray<NSValue *> *_readers;
    unsigned _readcount;
    dispatch_semaphore_t _lockReadersMetadata;

    pthread_t _writer;
    dispatch_semaphore_t _writing;
    dispatch_semaphore_t _lockWritersMetadata;
}

- (nonnull instancetype)init
{
    if (self = [super init]) {
        _lockReadersMetadata = dispatch_semaphore_create(1);
        _readcount = 0;
        _readers = [NSMutableArray new];

        _writing = dispatch_semaphore_create(1);
        _lockWritersMetadata = dispatch_semaphore_create(1);
        _writer = NULL;

        self.name = [super description];
    }
    return self;
}

- (BOOL)tryLockForReading
{
    BOOL success = YES;

    if(0 != dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_NOW)) {
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

    dispatch_semaphore_signal(_lockReadersMetadata);

    DEBUG_LOG(@"tryLockForReading: %d (%@)", success, self.name);
    return success;
}

- (void)lockForReading
{
    DEBUG_LOG(@"lockForReading (%@)", self.name);

    dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_FOREVER);

    [_readers addObject:[NSValue valueWithPointer:pthread_self()]];
    _readcount++;

    if(1 == _readcount) {
        dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);
    }

    dispatch_semaphore_signal(_lockReadersMetadata);
}

- (void)unlockForReading
{
    dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_FOREVER);

    [_readers removeObjectAtIndex:[_readers indexOfObject:[NSValue valueWithPointer:pthread_self()]]];
    _readcount--;

    if(0 == _readcount) {
        dispatch_semaphore_signal(_writing);
    }

    dispatch_semaphore_signal(_lockReadersMetadata);

    DEBUG_LOG(@"unlockForReading (%@)", self.name);
}

- (BOOL)tryLockForWriting
{
    DEBUG_LOG(@"tryLockForWriting (%@)", self.name);
    BOOL success = !dispatch_semaphore_wait(_writing, DISPATCH_TIME_NOW);
    
    if (success) {
        dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_FOREVER);
        _writer = pthread_self();
        dispatch_semaphore_signal(_lockReadersMetadata);
    }
    
    return success;
}

- (void)lockForWriting
{
    DEBUG_LOG(@"lockForWriting (%@)", self.name);
    dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_FOREVER);

    dispatch_semaphore_wait(_writing, DISPATCH_TIME_FOREVER);

    dispatch_semaphore_wait(_lockWritersMetadata, DISPATCH_TIME_FOREVER);
    _writer = pthread_self();
    dispatch_semaphore_signal(_lockWritersMetadata);

    dispatch_semaphore_signal(_lockReadersMetadata);
}

- (void)unlockForWriting
{
    dispatch_semaphore_wait(_lockWritersMetadata, DISPATCH_TIME_FOREVER);
    _writer = NULL;
    dispatch_semaphore_signal(_lockWritersMetadata);
    
    dispatch_semaphore_signal(_writing);
    DEBUG_LOG(@"unlockForWriting (%@)", self.name);
}

- (void)holdingWriteLock
{
    dispatch_semaphore_wait(_lockWritersMetadata, DISPATCH_TIME_FOREVER);

    if (_writer != pthread_self()) {
        [NSException raise:NSInternalInconsistencyException format:@"No write scope"];
    }

    dispatch_semaphore_signal(_lockWritersMetadata);
}

- (void)holdingReadLock
{
    dispatch_semaphore_wait(_lockReadersMetadata, DISPATCH_TIME_FOREVER);
    
    if (![_readers containsObject:[NSValue valueWithPointer:pthread_self()]]) {
        [NSException raise:NSInternalInconsistencyException format:@"No read scope"];
    }
    
    dispatch_semaphore_signal(_lockReadersMetadata);
}

@end
