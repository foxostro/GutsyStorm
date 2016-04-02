//
//  SyscallWrappers.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/14/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import "SyscallWrappers.h"

void raiseExceptionForPOSIXError(int error, NSString * _Nonnull desc)
{
    char errorMsg[LINE_MAX];
    strerror_r(error, errorMsg, LINE_MAX);
    [NSException raise:@"POSIX error" format:@"%@%s", desc, errorMsg];
}

int Open(NSURL * _Nonnull url, int oflags, mode_t mode)
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
    while(close(fd) < 0) {
        if(errno != EINTR) {
            raiseExceptionForPOSIXError(errno, [NSString stringWithFormat:@"error with close(%d)", fd]);
        }
    }
}