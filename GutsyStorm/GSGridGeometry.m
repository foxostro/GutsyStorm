//
//  GSGridGeometry.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSGrid.h"
#import "GSChunkGeometryData.h"
#import "GSGridGeometry.h"

@implementation GSGridGeometry
{
    NSURL *_folder;
}

- (nonnull instancetype)initWithName:(nonnull NSString *)name
                          cacheFolder:(nonnull NSURL *)folder
                              factory:(nonnull GSGridItemFactory)factory
{
    if (self = [super initWithName:name factory:factory]) {
        _folder = folder;
    }
    return self;
}

- (void)willInvalidateItem:(nonnull NSObject <GSGridItem> * __unused)item atPoint:(vector_float3)p
{
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSString *fileName = [GSChunkGeometryData fileNameForGeometryDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end
