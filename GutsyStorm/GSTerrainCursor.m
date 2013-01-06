//
//  GSTerrainCursor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import <GLKit/GLKMath.h>
#import "GSTerrainCursor.h"

@implementation GSTerrainCursor
{
    GSCube *_cursor;
}

- (id)init
{
    self = [super init];
    if(self) {
        _cursorIsActive = NO;
        _cursorPos = _cursorPlacePos = GLKVector3Make(0, 0, 0);
        _cursor = [[GSCube alloc] init];
        [_cursor generateVBO];
    }
    return self;
}

- (void)dealloc
{
    [_cursor release];
    [super dealloc];
}

- (void)drawWithEdgeOffset:(GLfloat)edgeOffset
{
    if(_cursorIsActive) {
        glDepthRange(0.0, 1.0 - edgeOffset);
        glPushMatrix();
        glTranslatef(_cursorPos.x, _cursorPos.y, _cursorPos.z);
        [_cursor draw];
        glPopMatrix();
    }
}

@end
