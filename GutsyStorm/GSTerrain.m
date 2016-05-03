//
//  GSTerrain.m
//  GutsyStorm
//
//  Created by Andrew Fox on 10/28/12.
//  Copyright © 2012-2016 Andrew Fox. All rights reserved.
//

#import "GSIntegerVector3.h"
#import "GSVoxel.h"
#import "GSNoise.h"
#import "GSCube.h"
#import "GSTerrainCursor.h"
#import "GSTerrainChunkStore.h"
#import "GSTextureArray.h"
#import "GSShader.h"
#import "GSCamera.h"
#import "GSTerrain.h"
#import "GSRay.h"
#import "GSMatrixUtils.h"
#import "GSTerrainJournal.h"
#import "GSTerrainRayMarcher.h"
#import "GSTerrainGenerator.h"
#import "GSTerrainModifyBlockOperation.h"

#import <OpenGL/gl.h>

int checkGLErrors(void); // TODO: find a new home for checkGLErrors()


@implementation GSTerrain
{
    GSCamera *_camera;
    GSTextureArray *_textureArray;
    GSTerrainChunkStore *_chunkStore;
    GSTerrainRayMarcher *_chunkStoreRayMarcher;
    GSTerrainCursor *_cursor;
}

@synthesize chunkStore = _chunkStore;

- (nonnull NSString *)newShaderSourceStringFromFileAt:(nonnull NSString *)path
{
    NSError *error;
    NSString *str = [[NSString alloc] initWithContentsOfFile:path
                                                    encoding:NSMacOSRomanStringEncoding
                                                       error:&error];
    if (!str) {
        NSLog(@"Error reading file at %@: %@", path, [error localizedFailureReason]);
        return @"";
    }
    
    return str;
}

- (nonnull GSShader *)newCursorShader
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *vertFn = [bundle pathForResource:@"cursor.vert" ofType:@"txt"];
    NSString *fragFn = [bundle pathForResource:@"cursor.frag" ofType:@"txt"];
    
    NSString *vertSrc = [self newShaderSourceStringFromFileAt:vertFn];
    NSString *fragSrc = [self newShaderSourceStringFromFileAt:fragFn];
    
    GSShader *cursorShader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    
    [cursorShader bind];
    [cursorShader bindUniformWithMatrix4x4:matrix_identity_float4x4 name:@"mvp"];
    [cursorShader unbind];
    
    assert(checkGLErrors() == 0);

    return cursorShader;
}

- (nonnull GSShader *)newTerrainShader
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *vertFn = [bundle pathForResource:@"terrain.vert" ofType:@"txt"];
    NSString *fragFn = [bundle pathForResource:@"terrain.frag" ofType:@"txt"];
    
    NSString *vertSrc = [self newShaderSourceStringFromFileAt:vertFn];
    NSString *fragSrc = [self newShaderSourceStringFromFileAt:fragFn];
    
    GSShader *terrainShader = [[GSShader alloc] initWithVertexShaderSource:vertSrc fragmentShaderSource:fragSrc];
    
    [terrainShader bind];
    [terrainShader bindUniformWithInt:0 name:@"tex"]; // texture unit 0
    [terrainShader bindUniformWithMatrix4x4:matrix_identity_float4x4 name:@"mvp"];
    [terrainShader unbind];

    assert(checkGLErrors() == 0);
    
    return terrainShader;
}

- (nonnull instancetype)initWithJournal:(nonnull GSTerrainJournal *)journal
                                 camera:(nonnull GSCamera *)cam
                              glContext:(nonnull NSOpenGLContext *)context
{
    assert(checkGLErrors() == 0);

    if (self = [super init]) {
        _journal = journal;
        _camera = cam;
        _textureArray = [[GSTextureArray alloc] initWithImagePath:[[NSBundle mainBundle] pathForResource:@"terrain"
                                                                                                  ofType:@"png"]
                                                      numTextures:4];
        _chunkStore = [[GSTerrainChunkStore alloc] initWithJournal:journal
                                                            camera:cam
                                                     terrainShader:[self newTerrainShader]
                                                         glContext:context
                                                         generator:[[GSTerrainGenerator alloc] initWithRandomSeed:journal.randomSeed]];
        _chunkStoreRayMarcher = [[GSTerrainRayMarcher alloc] initWithChunkStore:_chunkStore];
        _cursor = [[GSTerrainCursor alloc] initWithChunkStore:_chunkStore
                                                       camera:cam
                                                   cube:[[GSCube alloc] initWithContext:context
                                                                                 shader:[self newCursorShader]]];
    }
    return self;
}

- (void)draw
{
    static const float edgeOffset = 1e-4;
    glDepthRange(edgeOffset, 1.0); // Use glDepthRange so the block cursor is properly offset from the block itself.

    [_textureArray bind];
    [_chunkStore drawActiveChunks];
    [_textureArray unbind];
    
    glDepthRange(0.0, 1.0 - edgeOffset);
    [_cursor draw];

    glDepthRange(0.0, 1.0);
}

- (void)updateWithDeltaTime:(float)dt cameraModifiedFlags:(unsigned)cameraModifiedFlags
{
    [_cursor updateWithCameraModifiedFlags:cameraModifiedFlags];
    [_chunkStore updateWithCameraModifiedFlags:cameraModifiedFlags];
}

- (void)memoryPressure:(dispatch_source_memorypressure_flags_t)status
{
    [_chunkStore memoryPressure:status];
}

- (void)printInfo
{
    [_chunkStore printInfo];
}

- (void)placeBlockUnderCrosshairs
{
    if(_cursor.cursorIsActive) {
        GSVoxel block;
        bzero(&block, sizeof(GSVoxel));
        block.opaque = YES;
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_CUBE;
        
        GSTerrainModifyBlockOperation *placeBlock;
        placeBlock = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                         block:block
                                                                      position:_cursor.cursorPlacePos
                                                                       journal:_journal];
        [placeBlock main];

        [_cursor recalcCursorPosition];
    }
}

- (void)removeBlockUnderCrosshairs
{
    if(_cursor.cursorIsActive) {
        GSVoxel block;
        bzero(&block, sizeof(GSVoxel));
        block.dir = VOXEL_DIR_NORTH;
        block.type = VOXEL_TYPE_EMPTY;
        
        GSTerrainModifyBlockOperation *placeBlock;
        placeBlock = [[GSTerrainModifyBlockOperation alloc] initWithChunkStore:_chunkStore
                                                                         block:block
                                                                      position:_cursor.cursorPos
                                                                       journal:_journal];
        [placeBlock main];
        
        [_cursor recalcCursorPosition];
    }
}

- (void)shutdown
{
    [_chunkStore shutdown];
    _chunkStore = nil;

    [_journal flush];
    _journal = nil;
}

@end
