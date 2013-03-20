//
//  GSGridGeometry.m
//  GutsyStorm
//
//  Created by Andrew Fox on 3/19/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKVector3.h>
#import <GLKit/GLKQuaternion.h>
#import "GSIntegerVector3.h"
#import "GSGrid.h"
#import "GSChunkGeometryData.h"
#import "GSGridGeometry.h"

@implementation GSGridGeometry
{
    NSURL *_folder;
}

- (id)initWithCacheFolder:(NSURL *)folder factory:(grid_item_factory_t)factory
{
    if(self = [super initWithFactory:factory]) {
        _folder = folder;
    }
    
    return self;
}

- (void)willInvalidateItem:(NSObject <GSGridItem> *)item atPoint:(GLKVector3)p
{
    GLKVector3 minP = MinCornerForChunkAtPoint(p);
    NSString *fileName = [GSChunkGeometryData fileNameForGeometryDataFromMinP:minP];
    NSURL *url = [NSURL URLWithString:fileName relativeToURL:_folder];
    const char *path = [[url path] cStringUsingEncoding:NSMacOSRomanStringEncoding];
    unlink(path);
    NSLog(@"invalidated geometry at %@", fileName);
}

@end
