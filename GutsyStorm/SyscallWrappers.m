//
//  SyscallWrappers.m
//  GutsyStorm
//
//  Created by Andrew Fox on 1/14/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import "SyscallWrappers.h"

int Open(NSURL *url, int oflags, mode_t mode)
{
    assert(url);
    assert([url isFileURL]);

    int fd = 0;
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];

    do {
        fd = open(path, oflags, mode);
        if(fd == -1) {
            switch(errno)
            {
                case EINTR:
                    break;

                default:
                {
                    // TODO: graceful error handling
                    char errorMsg[LINE_MAX];
                    strerror_r(errno, errorMsg, LINE_MAX);
                    [NSException raise:@"POSIX error" format:@"error with open [error=%d] -- %s", errno, errorMsg];
                } break;
            }
        }
    } while(fd == -1);

    return fd;
}

void Close(int fd)
{
    while(close(fd) == -1)
    {
        switch(errno)
        {
            case EINTR:
                break;

            default:
            {
                // TODO: graceful error handling
                char errorMsg[LINE_MAX];
                strerror_r(errno, errorMsg, LINE_MAX);
                [NSException raise:@"POSIX error" format:@"error with close [fd=%d, error=%d] -- %s", fd, errno, errorMsg];
            } break;
        }
    }
}