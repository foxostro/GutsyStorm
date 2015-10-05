//
//  GSGridSunlight.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/25/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKVector3.h>
#import <GLKit/GLKQuaternion.h>
#import "GSIntegerVector3.h"
#import "Voxel.h"
#import "GSGrid.h"
#import "GSChunkSunlightData.h"
#import "GSGridSunlight.h"

@implementation GSGridSunlight
{
    NSURL *_folder;
}

- (instancetype)initWithCacheFolder:(NSURL *)folder factory:(grid_item_factory_t)factory
{
    if(self = [super initWithFactory:factory]) {
        _folder = folder;
    }

    return self;
}

- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(GLKVector3)p
{
    GLKVector3 minP = MinCornerForChunkAtPoint(p);
    NSString *fileName = [GSChunkSunlightData fileNameForSunlightDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
}

@end
