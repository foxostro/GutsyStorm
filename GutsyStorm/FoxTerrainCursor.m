//
//  FoxTerrainCursor.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright (c) 2012-2015 Andrew Fox. All rights reserved.
//

#import "FoxRay.h"
#import "FoxCamera.h"
#import "FoxMatrixUtils.h"
#import "FoxTerrainCursor.h"

#import <OpenGL/gl.h>
#import <simd/matrix.h>

@implementation FoxTerrainCursor
{
    FoxCube *_cursor;
}

- (instancetype)init
{
    @throw nil;
    return nil;
}

- (instancetype)initWithContext:(NSOpenGLContext *)context shader:(FoxShader *)shader
{
    self = [super init];
    if (self) {
        _cursorIsActive = NO;
        _cursorPos = _cursorPlacePos = vector_make(0, 0, 0);
        _cursor = [[FoxCube alloc] initWithContext:context shader:shader];
    }
    return self;
}

- (void)drawWithCamera:(FoxCamera *)camera edgeOffset:(GLfloat)edgeOffset
{
    if (!_cursorIsActive) {
        return;
    }

    glDepthRange(0.0, 1.0 - edgeOffset);

    matrix_float4x4 translation = matrix_from_translation(_cursorPos + vector_make(0.5f, 0.5f, 0.5f));
    matrix_float4x4 modelView = matrix_multiply(translation, camera.modelViewMatrix);
    matrix_float4x4 projection = camera.projectionMatrix;

    matrix_float4x4 mvp = matrix_multiply(modelView, projection);
    [_cursor drawWithModelViewProjectionMatrix:mvp];
}

@end