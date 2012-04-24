//
//  GSReaderWriterLock.h
//  GutsyStorm
//
//  Created by Andrew Fox on 4/23/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

@interface GSReaderWriterLock : NSObject
{
	dispatch_semaphore_t mutex;
	dispatch_semaphore_t writing;
	unsigned readcount;
}

- (void)lockForReading;
- (void)unlockForReading;
- (void)lockForWriting;
- (void)unlockForWriting;

@end
