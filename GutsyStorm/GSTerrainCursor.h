//
//  GSTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSRay.h"
#import "GSChunkStore.h"
#import "GSCube.h"

@interface GSTerrainCursor : NSObject

@property (assign) BOOL cursorIsActive;
@property (assign) GLKVector3 cursorPos;
@property (assign) GLKVector3 cursorPlacePos;

- (void)drawWithEdgeOffset:(GLfloat)edgeOffset;

@end
