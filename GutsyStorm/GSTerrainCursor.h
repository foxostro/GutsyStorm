//
//  GSTerrainCursor.h
//  GutsyStorm
//
//  Created by Andrew Fox on 5/1/16.
//  Copyright © 2016 Andrew Fox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/vector.h>


@class GSTerrainChunkStore;
@class GSCamera;
@class GSCube;


@interface GSTerrainCursor : NSObject

@property (nonatomic, assign) BOOL cursorIsActive;
@property (nonatomic, assign) vector_float3 cursorPos;
@property (nonatomic, assign) vector_float3 cursorPlacePos;

- (nonnull instancetype)init NS_UNAVAILABLE;

- (nonnull instancetype)initWithChunkStore:(nonnull GSTerrainChunkStore *)chunkStore
                                    camera:(nonnull GSCamera *)camera
                                      cube:(nonnull GSCube *)cube NS_DESIGNATED_INITIALIZER;

- (void)updateWithCameraModifiedFlags:(unsigned)flags;

- (void)draw;

- (void)recalcCursorPosition;

@end
