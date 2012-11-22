//
//  GSTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GSVector3.h"
#import "GSRay.h"
#import "GSChunkStore.h"
#import "GSCube.h"

@interface GSTerrainCursor : NSObject
{
    BOOL cursorIsActive;
    GSVector3 cursorPos;
    GSVector3 cursorPlacePos;
    GSCube *cursor;
}

@property (assign) BOOL cursorIsActive;
@property (assign) GSVector3 cursorPos;
@property (assign) GSVector3 cursorPlacePos;

- (void)drawWithEdgeOffset:(GLfloat)edgeOffset;

@end
