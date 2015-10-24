//
//  FoxGridSunlight.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013-2015 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FoxIntegerVector3.h"
#import "GSVoxel.h"
#import "FoxGrid.h"
#import "FoxChunkSunlightData.h"
#import "FoxGridSunlight.h"

@implementation FoxGridSunlight
{
    NSURL *_folder;
}

- (instancetype)initWithName:(NSString *)name
                 cacheFolder:(NSURL *)folder
                     factory:(fox_grid_item_factory_t)factory
{
    if (self = [super initWithName:name factory:factory]) {
        _folder = folder;
    }
    return self;
}

- (void)willInvalidateItem:(NSObject <FoxGridItem> *)item atPoint:(vector_float3)p
{
    vector_float3 minP = MinCornerForChunkAtPoint(p);
    NSString *fileName = [FoxChunkSunlightData fileNameForSunlightDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end
