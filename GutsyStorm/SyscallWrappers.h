//
//  SyscallWrappers.h
//  GutsyStorm
//
//  Created by Andrew Fox on 1/14/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

void raiseExceptionForPOSIXError(int error, NSString *desc);

int Open(NSURL *url, int oflags, mode_t mode);
void Close(int fd);