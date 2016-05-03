//
//  GSChunkVAO.h
//  GutsyStorm
//
//  Created by Andrew Fox on 3/17/13.
//  Copyright © 2013-2016 Andrew Fox. All rights reserved.
//

@class GSChunkGeometryData;

@interface GSChunkVAO : NSObject <GSGridItem>

@property (nonatomic, nonnull, readonly) NSOpenGLContext *glContext;

- (nonnull instancetype)initWithChunkGeometry:(nonnull GSChunkGeometryData *)geometry
                                    glContext:(nonnull NSOpenGLContext *)glContext;

/* Assumes the caller has already locked the context on the current thread. */
- (void)draw;

@end
