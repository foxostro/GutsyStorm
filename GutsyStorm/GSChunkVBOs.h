//
//  GSChunkVBOs.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright (c) 2013 Andrew Fox. All rights reserved.
//

@class GSChunkGeometryData;

@interface GSChunkVBOs : NSObject <GSGridItem>

- (instancetype)initWithChunkGeometry:(GSChunkGeometryData *)geometry
                            glContext:(NSOpenGLContext *)glContext;

// Assumes the caller has already locked the context on the current thread.
- (void)draw;

@end
