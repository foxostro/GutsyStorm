//
//  GSRenderTexture.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/31/12.
//  Copyright 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>

#define CUBE_MAP_POSITIVE_X    (0)
#define CUBE_MAP_NEGATIVE_X    (1)
#define CUBE_MAP_POSITIVE_Y    (2)
#define CUBE_MAP_NEGATIVE_Y    (3)
#define CUBE_MAP_POSITIVE_Z    (4)
#define CUBE_MAP_NEGATIVE_Z    (5)


@interface GSRenderTexture : NSObject

@property (assign, nonatomic) NSRect dimensions;
@property (readonly, nonatomic) BOOL isCubeMap;

- (instancetype)initWithDimensions:(NSRect)dimensions isCubeMap:(BOOL)isCubeMap;
- (void)startRender;
- (void)startRenderForCubeFace:(unsigned)face;
- (void)finishRender;
- (void)bind;
- (void)unbind;

@end
