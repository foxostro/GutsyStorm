//
//  SyscallWrappers.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/14/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "SyscallWrappers.h"

void raiseExceptionForPOSIXError(int error, NSString *desc)
{
    char errorMsg[LINE_MAX];
    strerror_r(error, errorMsg, LINE_MAX);
    [NSException raise:@"POSIX error" format:@"%@%s", desc, errorMsg];
}

int Open(NSURL *url, int oflags, mode_t mode)
{
    assert(url);
    assert([url isFileURL]);

    int fd = 0;
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];

    do {
        fd = open(path, oflags, mode);
        if(fd < 0) {
            switch(errno)
            {
                case EINTR:
                    break;

                default:
                    raiseExceptionForPOSIXError(errno, [NSString stringWithFormat:@"error with open(%d)", fd]);
                    break;
            }
        }
    } while(fd < 0);

    return fd;
}

void Close(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);

    if(flags < 0) {
        raiseExceptionForPOSIXError(errno, [NSString stringWithFormat:@"error with fcntl(%d, F_GETFL, 0)", fd]);
    }

    if(!(flags & O_NONBLOCK) && fcntl(fd, F_SETFL, flags|O_NONBLOCK) < 0) {
        raiseExceptionForPOSIXError(errno, [NSString stringWithFormat:@"error with fcntl(%d, F_SETFL, flags|O_NONBLOCK)", fd]);
    }

    if(close(fd) < 0) {
        raiseExceptionForPOSIXError(errno, [NSString stringWithFormat:@"error with close(%d)", fd]);
    }
}