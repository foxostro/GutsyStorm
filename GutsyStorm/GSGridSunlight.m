//
//  GSGridSunlight.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSIntegerVector3.h"
#import "GSVoxel.h"
#import "GSGrid.h"
#import "GSChunkSunlightData.h"
#import "GSGridSunlight.h"

@implementation GSGridSunlight
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

- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(vector_float3)p
{
    vector_float3 minP = GSMinCornerForChunkAtPoint(p);
    NSString *fileName = [GSChunkSunlightData fileNameForSunlightDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end
