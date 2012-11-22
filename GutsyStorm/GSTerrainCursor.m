//
//  GSTerrainCursor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012 Andrew Fox. All rights reserved.
//

#import "GSTerrainCursor.h"

@implementation GSTerrainCursor

@synthesize cursorIsActive;
@synthesize cursorPos;
@synthesize cursorPlacePos;

- (id)init
{
    self = [super init];
    if(self) {
        cursorIsActive = NO;
        cursorPos = cursorPlacePos = GSVector3_Make(0, 0, 0);
        cursor = [[GSCube alloc] init];
        [cursor generateVBO];
    }
    return self;
}

- (void)dealloc
{
    [cursor release];
    [super dealloc];
}

- (void)drawWithEdgeOffset:(GLfloat)edgeOffset
{
    if(cursorIsActive) {
        glDepthRange(0.0, 1.0 - edgeOffset);
        glPushMatrix();
        glTranslatef(cursorPos.x, cursorPos.y, cursorPos.z);
        [cursor draw];
        glPopMatrix();
    }
}

@end
